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
    @State private var showFailedDownloads = false

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
                HStack {
                    Button("Download") {
                        downloadManager.startDownload(statusManager: statusManager, modelContext: modelContext)
                    }
                    .disabled(downloadManager.urlString.isEmpty || !downloadManager.dependenciesInstalled)

                    if !downloadManager.failedDownloads.isEmpty {
                        Spacer()
                        Button("Show Failed Items (\(downloadManager.failedDownloads.count))") {
                            showFailedDownloads = true
                        }
                        .foregroundStyle(.red)
                    }
                }
            }

            if !statusManager.logOutput.isEmpty {
                Section("Process Log") {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(statusManager.logOutput)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(4)
                                .id("bottom")
                        }
                        .frame(height: 150)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(8)
                        .onChange(of: statusManager.logOutput) { _ in
                            withAnimation {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .onAppear {
            downloadManager.checkDependencies()
        }
        .sheet(isPresented: $showFailedDownloads) {
            FailedDownloadsView(items: downloadManager.failedDownloads)
        }
    }
}

struct FailedDownloadsView: View {
    var items: [DownloadManager.FailedDownloadItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Failed Downloads")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }
            .padding()

            Table(items) {
                TableColumn("Title", value: \.title)
                TableColumn("URL", value: \.url)
                TableColumn("Error", value: \.error)
            }

            HStack {
                Spacer()
                Button("Download CSV") {
                    saveCSV()
                }
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 300)
    }

    private func saveCSV() {
        let header = "Title,URL,Error\n"
        let csvContent = items.map { item in
            let escapedTitle = item.title.replacingOccurrences(of: "\"", with: "\"\"")
            let escapedError = item.error.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escapedTitle)\",\"\(item.url)\",\"\(escapedError)\""
        }.joined(separator: "\n")

        let finalString = header + csvContent

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "failed_downloads.csv"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try finalString.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("Failed to save CSV: \(error)")
                }
            }
        }
    }
}
