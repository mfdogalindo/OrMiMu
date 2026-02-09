//
//  YouTubeDownloadView.swift
//  OrMiMu
//
//  Created by Jules on 2024-05-22.
//

import SwiftUI
import SwiftData

struct YouTubeDownloadView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var statusManager: StatusManager
    @EnvironmentObject var downloadManager: DownloadManager

    var body: some View {
        Form {
            if !downloadManager.dependenciesInstalled {
                Section("Dependencies") {
                    if downloadManager.isInstallingDependencies {
                        ProgressView("Installing components (yt-dlp & ffmpeg)...")
                    } else {
                        Button("Install Dependencies") {
                            downloadManager.installDependencies(statusManager: statusManager)
                        }
                    }
                }
            }

            Section("Video URL") {
                TextField("https://...", text: $downloadManager.urlString)
            }

            Section("Settings") {
                Picker("Format", selection: $downloadManager.selectedFormat) {
                    ForEach(downloadManager.formats, id: \.self) { format in
                        Text(format.uppercased()).tag(format)
                    }
                }
                .pickerStyle(MenuPickerStyle())

                if downloadManager.selectedFormat == "mp3" || downloadManager.selectedFormat == "m4a" {
                    Picker("Bitrate (kbps)", selection: $downloadManager.selectedBitrate) {
                        ForEach(downloadManager.bitrates, id: \.self) { bitrate in
                            Text(bitrate).tag(bitrate)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }

            Section("Metadata Override (Optional)") {
                TextField("Artist", text: $downloadManager.artist)
                TextField("Album", text: $downloadManager.album)
                TextField("Genre", text: $downloadManager.genre)
                TextField("Year", text: $downloadManager.year)
            }

            if downloadManager.isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: statusManager.progress)
                    Text(statusManager.statusDetail.isEmpty ? "Downloading..." : statusManager.statusDetail)
                        .font(.caption)

                    Button("Stop Download") {
                        downloadManager.cancelDownload(statusManager: statusManager)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button("Download") {
                    downloadManager.startDownload(statusManager: statusManager, modelContext: modelContext)
                }
                .disabled(downloadManager.urlString.isEmpty || !downloadManager.dependenciesInstalled)
            }
        }
        .padding()
        .onAppear {
            downloadManager.checkDependencies()
        }
    }
}
