//
//  DownloadManager.swift
//  OrMiMu
//
//  Created by Jules on 2024-05-22.
//

import SwiftUI
import SwiftData
import Foundation

@MainActor
class DownloadManager: ObservableObject {
    @Published var urlString: String = ""
    @Published var artist: String = ""
    @Published var album: String = ""
    @Published var genre: String = ""
    @Published var year: String = ""

    @Published var isDownloading: Bool = false
    @Published var isInstallingDependencies: Bool = false
    @Published var dependenciesInstalled: Bool = false

    // Preferences
    @AppStorage("downloadFormat") var defaultFormat: String = "mp3"
    @AppStorage("downloadBitrate") var defaultBitrate: String = "256"
    @Published var selectedFormat: String = "mp3"
    @Published var selectedBitrate: String = "256"

    let formats = ["mp3", "m4a", "flac", "wav"]
    let bitrates = ["128", "192", "256", "320"]

    init() {
        self.selectedFormat = UserDefaults.standard.string(forKey: "downloadFormat") ?? "mp3"
        self.selectedBitrate = UserDefaults.standard.string(forKey: "downloadBitrate") ?? "256"
        checkDependencies()
    }

    func checkDependencies() {
        dependenciesInstalled = DependencyManager.shared.isInstalled()
    }

    func installDependencies(statusManager: StatusManager) {
        isInstallingDependencies = true
        statusManager.isBusy = true
        Task {
            do {
                try await DependencyManager.shared.install { progress in
                    // Update progress if needed
                }
                await MainActor.run {
                    dependenciesInstalled = true
                    isInstallingDependencies = false
                    statusManager.isBusy = false
                    statusManager.statusMessage = "Dependencies installed successfully!"
                }
            } catch {
                await MainActor.run {
                    statusManager.statusMessage = "Error installing dependencies: \(error.localizedDescription)"
                    isInstallingDependencies = false
                    statusManager.isBusy = false
                }
            }
        }
    }

    func startDownload(statusManager: StatusManager, modelContext: ModelContext) {
        guard let url = URL(string: urlString) else {
            statusManager.statusMessage = "Error: Invalid URL"
            return
        }

        // Capture override values to use in callback safely
        let artistOverride = self.artist
        let albumOverride = self.album
        let genreOverride = self.genre
        let yearOverride = self.year

        isDownloading = true
        statusManager.isBusy = true
        statusManager.statusMessage = "Starting download..."
        statusManager.progress = 0.0
        statusManager.statusDetail = ""

        Task {
            do {
                // Pass a closure to handle each file as it finishes immediately
                _ = try await YouTubeService.shared.download(
                    url: url,
                    format: selectedFormat,
                    bitrate: selectedBitrate,
                    statusManager: statusManager,
                    artist: nil,
                    album: nil,
                    genre: nil,
                    year: nil
                ) { filePath in
                    // This closure is called when a file is completely finished (downloaded + converted)

                    // 1. Read Metadata
                    var currentTags = await MetadataService.readMetadata(url: URL(fileURLWithPath: filePath))

                    // 2. Apply Overrides
                    let finalArtist = !artistOverride.isEmpty ? artistOverride : currentTags.artist
                    let finalAlbum = !albumOverride.isEmpty ? albumOverride : currentTags.album
                    let finalGenre = !genreOverride.isEmpty ? genreOverride : currentTags.genre
                    let finalYear = !yearOverride.isEmpty ? yearOverride : currentTags.year

                    if !artistOverride.isEmpty || !albumOverride.isEmpty || !genreOverride.isEmpty || !yearOverride.isEmpty {
                         try? await MetadataService.updateMetadata(
                            filePath: filePath,
                            title: currentTags.title,
                            artist: finalArtist,
                            album: finalAlbum,
                            genre: finalGenre,
                            year: finalYear
                        )
                        // Update local struct for insertion
                        currentTags.artist = finalArtist
                        currentTags.album = finalAlbum
                        currentTags.genre = finalGenre
                        currentTags.year = finalYear
                    }

                    // 3. Add to Library immediately
                    await MainActor.run {
                        // Check for duplicates
                        let descriptor = FetchDescriptor<SongItem>(
                            predicate: #Predicate { $0.filePath == filePath }
                        )
                        if let existingCount = try? modelContext.fetchCount(descriptor), existingCount == 0 {
                            let song = SongItem(
                                title: currentTags.title.isEmpty ? URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent : currentTags.title,
                                artist: currentTags.artist.isEmpty ? "Unknown Artist" : currentTags.artist,
                                album: currentTags.album.isEmpty ? "Unknown Album" : currentTags.album,
                                genre: currentTags.genre.isEmpty ? "Unknown Genre" : currentTags.genre,
                                year: currentTags.year.isEmpty ? "Unknown Year" : currentTags.year,
                                filePath: filePath,
                                duration: 0 // Ideally get duration
                            )
                            modelContext.insert(song)
                            try? modelContext.save()
                        }
                    }
                }

                await MainActor.run {
                    statusManager.statusMessage = "Download Complete!"
                    isDownloading = false
                    statusManager.isBusy = false
                    statusManager.reset()
                    urlString = ""
                    // Clear overrides
                    artist = ""
                    album = ""
                    genre = ""
                    year = ""
                }
            } catch {
                await MainActor.run {
                    statusManager.statusMessage = "Error: \(error.localizedDescription)"
                    isDownloading = false
                    statusManager.isBusy = false
                    statusManager.reset()
                }
            }
        }
    }

    func cancelDownload(statusManager: StatusManager) {
        statusManager.cancelAction?()
        isDownloading = false
        statusManager.isBusy = false
        statusManager.statusMessage = "Download stopped by user."
        statusManager.reset()
    }
}
