//
//  DeviceManagerView.swift
//  OrMiMu
//
//  Created by Jules on 08/02/26.
//

import SwiftUI
import SwiftData
import AppKit

struct DeviceManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var statusManager: StatusManager
    @EnvironmentObject var context: DeviceManagerContext

    @Query(sort: \PlaylistItem.name) private var allPlaylists: [PlaylistItem]

    // We use context for state, but fileImporter needs a binding.
    @State private var showFileImporter = false

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header / Device Selection
            HStack {
                Image(systemName: "externaldrive.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading) {
                    Text("External Device Manager")
                        .font(.headline)
                    if let url = context.deviceRoot {
                        Text(url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("No device selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Select Device / Folder") {
                    showFileImporter = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if let _ = context.deviceRoot {
                ScrollView {
                    VStack(spacing: 20) {

                        // MARK: - Device Info & Stats
                        GroupBox(label: Label("Device Information", systemImage: "info.circle")) {
                            HStack(alignment: .top, spacing: 20) {
                                VStack(alignment: .leading, spacing: 10) {
                                    TextField("Alias", text: $context.config.alias)
                                        .textFieldStyle(.roundedBorder)
                                        .onChange(of: context.config.alias) { _, _ in context.saveConfig() }

                                    TextField("Description", text: $context.config.description)
                                        .textFieldStyle(.roundedBorder)
                                        .onChange(of: context.config.description) { _, _ in context.saveConfig() }
                                }
                                .frame(maxWidth: 300)

                                Divider()

                                VStack(alignment: .leading) {
                                    if let info = context.volumeInfo {
                                        let totalGB = Double(info.total) / 1_000_000_000
                                        let freeGB = Double(info.free) / 1_000_000_000
                                        let usedGB = totalGB - freeGB
                                        let percent = totalGB > 0 ? usedGB / totalGB : 0

                                        Text("Storage Usage")
                                            .font(.caption)
                                            .bold()

                                        ProgressView(value: percent)
                                            .tint(percent > 0.9 ? .red : .accentColor)

                                        HStack {
                                            Text("\(String(format: "%.1f", freeGB)) GB Free")
                                            Spacer()
                                            Text("\(String(format: "%.1f", totalGB)) GB Total")
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    } else {
                                        Text("Storage info unavailable")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding()
                        }

                        // MARK: - Sync Settings
                        GroupBox(label: Label("Configuration", systemImage: "gearshape")) {
                            Form {
                                Picker("Target Format", selection: $context.targetFormat) {
                                    Text("MP3 (Universal)").tag("mp3")
                                    Text("AAC (M4A)").tag("m4a")
                                    Text("FLAC (Lossless)").tag("flac")
                                }
                                .onChange(of: context.targetFormat) { _, newValue in
                                    // Update config supported formats ensuring target is first
                                    context.config.supportedFormats = [newValue]
                                    context.saveConfig()
                                }

                                Toggle("Simple Device Mode (Flat Structure)", isOn: $context.config.isSimpleDevice)
                                    .onChange(of: context.config.isSimpleDevice) { _, _ in context.saveConfig() }

                                if context.config.isSimpleDevice {
                                    Toggle("Randomize Order (0001_Song...)", isOn: $context.config.randomizeCopy)
                                        .padding(.leading)
                                        .onChange(of: context.config.randomizeCopy) { _, _ in context.saveConfig() }
                                }

                                Text(context.config.isSimpleDevice ?
                                     "Files will be placed in the root folder." :
                                     "Files will be organized in folders by Playlist.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding()
                        }

                        // MARK: - Content Selection
                        GroupBox(label: Label("Select Playlists to Sync", systemImage: "music.note.list")) {
                            List {
                                ForEach(allPlaylists) { playlist in
                                    HStack {
                                        Toggle(isOn: Binding(
                                            get: { context.selectedPlaylists.contains(playlist.id) },
                                            set: { isSelected in
                                                if isSelected {
                                                    context.selectedPlaylists.insert(playlist.id)
                                                } else {
                                                    context.selectedPlaylists.remove(playlist.id)
                                                }
                                            }
                                        )) {
                                            Text(playlist.name)
                                        }
                                        Spacer()
                                        Text("\(playlist.songs?.count ?? 0) songs")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(height: 200)
                        }

                        // MARK: - Actions
                        HStack {
                            Button(action: exportCSV) {
                                Label("Export CSV List", systemImage: "doc.text")
                            }

                            Spacer()

                            Button(action: startSync) {
                                HStack {
                                    if context.isSyncing {
                                        ProgressView().controlSize(.small)
                                    }
                                    Text(context.isSyncing ? "Syncing..." : "Sync Now")
                                        .bold()
                                }
                                .padding(.horizontal)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(context.isSyncing || context.selectedPlaylists.isEmpty)
                        }
                        .padding(.bottom)

                    }
                    .padding()
                }
            } else {
                VStack {
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                        .padding()
                    Text("Select a folder or drive to manage.")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    context.deviceRoot = url
                    context.refreshDeviceState()
                }
            case .failure(let error):
                statusManager.statusMessage = "Error selecting folder: \(error.localizedDescription)"
            }
        }
    }

    private func startSync() {
        guard let url = context.deviceRoot else { return }

        context.isSyncing = true
        statusManager.isBusy = true

        // 1. Prepare DTOs on MainActor (SwiftData Access)
        let playlistsToSync = allPlaylists.filter { context.selectedPlaylists.contains($0.id) }
        let playlistDTOs = playlistsToSync.map { playlist in
            PlaylistDTO(
                id: playlist.id,
                name: playlist.name,
                songs: (playlist.songs ?? []).map { song in
                    SongDTO(
                        id: song.id,
                        title: song.title,
                        artist: song.artist,
                        album: song.album,
                        filePath: song.filePath
                    )
                }
            )
        }

        // Capture dependencies
        let currentConfig = context.config
        let status = self.statusManager

        // 2. Offload to background
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try await DeviceService.shared.sync(playlists: playlistDTOs, to: url, config: currentConfig, status: status)
                }.value

                // 3. Update UI on completion
                context.isSyncing = false
                statusManager.isBusy = false
                // Refresh volume info
                context.refreshDeviceState()

            } catch {
                context.isSyncing = false
                statusManager.isBusy = false
                statusManager.statusMessage = "Sync failed: \(error.localizedDescription)"
            }
        }
    }

    private func exportCSV() {
        guard let deviceRoot = context.deviceRoot else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Device_Music_List.csv"

        panel.begin { response in
            if response == .OK, let outputURL = panel.url {
                generateAndSaveCSV(to: outputURL, deviceRoot: deviceRoot)
            }
        }
    }

    private func generateAndSaveCSV(to outputURL: URL, deviceRoot: URL) {
        // 1. Load Manifest
        let manifest = DeviceService.shared.loadManifest(from: deviceRoot)

        // 2. Fetch all songs for lookup
        let descriptor = FetchDescriptor<SongItem>()
        let allSongs = (try? modelContext.fetch(descriptor)) ?? []
        // Use dictionary for O(1) lookup: [SongID String : SongItem]
        // Note: Grouping by ID to handle potential duplicate IDs (though UUIDs should be unique)
        let lookup = Dictionary(grouping: allSongs, by: { $0.id.uuidString }).mapValues { $0.first! }

        // 3. Build CSV Content
        var csvString = "Relative Path,Title,Artist,Album,Duration,Format\n"

        // Sort by path for readability
        let sortedFiles = manifest.files.sorted(by: { $0.key < $1.key })

        for (path, songID) in sortedFiles {
            var title = "Unknown (ID: \(songID))"
            var artist = ""
            var album = ""
            var duration = ""
            var format = ""

            if let song = lookup[songID] {
                // Escape quotes for CSV
                title = song.title.replacingOccurrences(of: "\"", with: "\"\"")
                artist = song.artist.replacingOccurrences(of: "\"", with: "\"\"")
                album = song.album.replacingOccurrences(of: "\"", with: "\"\"")
                duration = formatDuration(song.duration)
                format = song.fileExtension
            }

            let row = "\"\(path)\",\"\(title)\",\"\(artist)\",\"\(album)\",\"\(duration)\",\"\(format)\"\n"
            csvString += row
        }

        // 4. Write to file
        do {
            try csvString.write(to: outputURL, atomically: true, encoding: .utf8)
            statusManager.statusMessage = "CSV Exported successfully."
        } catch {
            statusManager.statusMessage = "Failed to export CSV: \(error.localizedDescription)"
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let seconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
