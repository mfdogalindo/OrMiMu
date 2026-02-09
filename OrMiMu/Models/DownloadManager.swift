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
        statusManager.statusMessage = "Fetching video info..."
        statusManager.progress = 0.0
        statusManager.statusDetail = ""
        statusManager.logOutput = ""

        Task {
            do {
                // 1. Fetch items first (Sequential Logic)
                let videos = try await YouTubeService.shared.fetchVideoInfo(url: url)
                let totalItems = videos.count

                await MainActor.run {
                    statusManager.statusMessage = "Found \(totalItems) items. Starting download..."
                }

                // 2. Iterate and download sequentially
                for (index, video) in videos.enumerated() {
                    // Check for cancellation
                    if !isDownloading { break }

                    guard let videoUrlString = video.url, let videoUrl = URL(string: videoUrlString) else { continue }
                    let videoTitle = video.title ?? "Unknown Title"
                    let videoId = video.id ?? ""

                    // Check for duplicate in DB using sourceUrl OR filesystem (using new ID format)
                    var shouldSkip = false

                    await MainActor.run {
                        // 1. Check DB sourceUrl (Exact match or substring match for safety)
                        let descriptor = FetchDescriptor<SongItem>(
                            predicate: #Predicate { $0.sourceUrl == videoUrlString } // Basic URL check
                        )

                        if let existingSongs = try? modelContext.fetch(descriptor), let existing = existingSongs.first {
                            if FileManager.default.fileExists(atPath: existing.filePath) {
                                shouldSkip = true
                            }
                        }

                        // 2. Check DB sourceUrl using ID (stronger check against URL variations)
                        if !shouldSkip && !videoId.isEmpty {
                            // SwiftData predicates are limited, iterate if needed or use simple contains if supported.
                            // Since we might not support 'contains' well on all Strings in predicates, let's rely on the file system check as a robust fallback
                            // or try a broader fetch if performance allows. For now, filesystem check is very reliable with the new naming convention.
                        }
                    }

                    // 3. Check Filesystem for [ID] in filename (robust fallback)
                    if !shouldSkip && !videoId.isEmpty {
                        let outputFolder = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first?.appendingPathComponent("OrMiMu") ?? FileManager.default.temporaryDirectory.appendingPathComponent("OrMiMu_Downloads")
                        if let files = try? FileManager.default.contentsOfDirectory(atPath: outputFolder.path) {
                            for file in files {
                                if file.contains("[\(videoId)]") {
                                    shouldSkip = true
                                    break
                                }
                            }
                        }
                    }

                    if shouldSkip {
                        await MainActor.run {
                            statusManager.statusDetail = "Skipping duplicate: \(videoTitle)"
                            // Update progress even if skipped
                            let globalProgress = Double(index + 1) / Double(totalItems)
                            statusManager.progress = globalProgress
                        }
                        // Short delay to let user see "Skipping..." message
                        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                        continue
                    }

                    await MainActor.run {
                        statusManager.statusDetail = "Downloading item \(index + 1) of \(totalItems): \(videoTitle)"
                    }

                    // Download single item
                    _ = try await YouTubeService.shared.download(
                        url: videoUrl,
                        format: selectedFormat,
                        bitrate: selectedBitrate,
                        statusManager: statusManager,
                        progressCallback: { fileProgress in
                            // Calculate Global Progress
                            let globalProgress = (Double(index) + fileProgress) / Double(totalItems)
                            Task { @MainActor in
                                statusManager.progress = globalProgress
                            }
                        },
                        onFileFinished: { filePath in
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
                                 // Check for duplicates by file path first (legacy check)
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
                                         sourceUrl: videoUrl.absoluteString, // Save source URL
                                         duration: 0 // Ideally get duration
                                     )
                                     modelContext.insert(song)
                                     try? modelContext.save()
                                 }
                             }
                        }
                    )
                }

                await MainActor.run {
                    statusManager.statusMessage = "Download Complete!"
                    isDownloading = false
                    statusManager.isBusy = false
                    // Reset progress but keep log
                    statusManager.progress = 0.0
                    statusManager.statusDetail = ""
                    statusManager.cancelAction = nil

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
                    // Reset progress but keep log
                    statusManager.progress = 0.0
                    statusManager.statusDetail = ""
                    statusManager.cancelAction = nil
                }
            }
        }
    }

    func cancelDownload(statusManager: StatusManager) {
        statusManager.cancelAction?()
        isDownloading = false
        statusManager.isBusy = false
        statusManager.statusMessage = "Download stopped by user."
        // Reset progress but keep log
        statusManager.progress = 0.0
        statusManager.statusDetail = ""
        statusManager.cancelAction = nil
    }
}
