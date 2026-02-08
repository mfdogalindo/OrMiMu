//
//  YouTubeDownloadView.swift
//  OrMiMu
//
//  Created by Jules on 8/02/26.
//

import SwiftUI
import SwiftData

struct YouTubeDownloadView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var urlString: String = ""
    @State private var artist: String = ""
    @State private var album: String = ""
    @State private var genre: String = ""
    @State private var year: String = ""

    @State private var isDownloading = false
    @State private var statusMessage: String = ""

    var body: some View {
        Form {
            Section("Video URL") {
                TextField("https://...", text: $urlString)
            }

            Section("Metadata Override (Optional)") {
                TextField("Artist", text: $artist)
                TextField("Album", text: $album)
                TextField("Genre", text: $genre)
                TextField("Year", text: $year)
            }

            if isDownloading {
                ProgressView("Downloading...")
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .foregroundStyle(statusMessage.starts(with: "Error") ? .red : .green)
            }

            Button("Download") {
                startDownload()
            }
            .disabled(urlString.isEmpty || isDownloading)
        }
        .padding()
        .navigationTitle("YouTube Download")
    }

    private func startDownload() {
        guard let url = URL(string: urlString) else {
            statusMessage = "Error: Invalid URL"
            return
        }

        isDownloading = true
        statusMessage = "Starting..."

        Task {
            do {
                let filePath = try await YouTubeService.shared.download(
                    url: url,
                    artist: artist.isEmpty ? nil : artist,
                    album: album.isEmpty ? nil : album,
                    genre: genre.isEmpty ? nil : genre,
                    year: year.isEmpty ? nil : year
                )

                await MainActor.run {
                    addToLibrary(filePath: filePath)
                    statusMessage = "Success! Saved to \(filePath)"
                    isDownloading = false
                    urlString = ""
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Error: \(error.localizedDescription)"
                    isDownloading = false
                }
            }
        }
    }

    private func addToLibrary(filePath: String) {
        let song = SongItem(
            title: URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent,
            artist: artist.isEmpty ? "Unknown Artist" : artist,
            album: album.isEmpty ? "Unknown Album" : album,
            genre: genre.isEmpty ? "Unknown Genre" : genre,
            year: year.isEmpty ? "Unknown Year" : year,
            filePath: filePath,
            duration: 0 // Should ideally read duration from file
        )
        modelContext.insert(song)
    }
}
