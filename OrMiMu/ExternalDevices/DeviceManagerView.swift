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

    @Query(sort: \PlaylistItem.name) private var allPlaylists: [PlaylistItem]

    @State private var deviceRoot: URL?
    @State private var config: DeviceConfig = DeviceConfig()
    @State private var volumeInfo: (total: Int64, free: Int64)?
    @State private var selectedPlaylists: Set<UUID> = []
    @State private var showFileImporter = false
    @State private var isSyncing = false

    // UI Helpers
    @State private var targetFormat: String = "mp3"

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
                    if let url = deviceRoot {
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

            if let _ = deviceRoot {
                ScrollView {
                    VStack(spacing: 20) {

                        // MARK: - Device Info & Stats
                        GroupBox(label: Label("Device Information", systemImage: "info.circle")) {
                            HStack(alignment: .top, spacing: 20) {
                                VStack(alignment: .leading, spacing: 10) {
                                    TextField("Alias", text: $config.alias)
                                        .textFieldStyle(.roundedBorder)

                                    TextField("Description", text: $config.description)
                                        .textFieldStyle(.roundedBorder)
                                }
                                .frame(maxWidth: 300)

                                Divider()

                                VStack(alignment: .leading) {
                                    if let info = volumeInfo {
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
                                Picker("Target Format", selection: $targetFormat) {
                                    Text("MP3 (Universal)").tag("mp3")
                                    Text("AAC (M4A)").tag("m4a")
                                    Text("FLAC (Lossless)").tag("flac")
                                }
                                .onChange(of: targetFormat) { _, newValue in
                                    // Update config supported formats ensuring target is first
                                    config.supportedFormats = [newValue]
                                    saveConfig()
                                }

                                Toggle("Simple Device Mode (Flat Structure)", isOn: $config.isSimpleDevice)
                                    .onChange(of: config.isSimpleDevice) { _, _ in saveConfig() }

                                if config.isSimpleDevice {
                                    Toggle("Randomize Order (0001_Song...)", isOn: $config.randomizeCopy)
                                        .padding(.leading)
                                        .onChange(of: config.randomizeCopy) { _, _ in saveConfig() }
                                }

                                Text(config.isSimpleDevice ?
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
                                            get: { selectedPlaylists.contains(playlist.id) },
                                            set: { isSelected in
                                                if isSelected {
                                                    selectedPlaylists.insert(playlist.id)
                                                } else {
                                                    selectedPlaylists.remove(playlist.id)
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
                        Button(action: startSync) {
                            HStack {
                                if isSyncing {
                                    ProgressView().controlSize(.small)
                                }
                                Text(isSyncing ? "Syncing..." : "Sync Now")
                                    .bold()
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSyncing || selectedPlaylists.isEmpty)
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
                    loadDevice(url: url)
                }
            case .failure(let error):
                statusManager.statusMessage = "Error selecting folder: \(error.localizedDescription)"
            }
        }
    }

    private func loadDevice(url: URL) {
        self.deviceRoot = url

        // Load Volume Info
        if let info = DeviceService.shared.getVolumeInfo(url: url) {
            self.volumeInfo = info
        }

        // Load Config
        if let loadedConfig = DeviceService.shared.loadConfig(from: url) {
            self.config = loadedConfig
            self.targetFormat = loadedConfig.supportedFormats.first ?? "mp3"
        } else {
            // New Config
            self.config = DeviceConfig()
            saveConfig()
        }
    }

    private func saveConfig() {
        guard let url = deviceRoot else { return }
        try? DeviceService.shared.saveConfig(config, to: url)
    }

    private func startSync() {
        guard let url = deviceRoot else { return }

        isSyncing = true
        statusManager.isBusy = true

        // 1. Prepare DTOs on MainActor (SwiftData Access)
        let playlistsToSync = allPlaylists.filter { selectedPlaylists.contains($0.id) }
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
        let currentConfig = self.config
        let status = self.statusManager

        // 2. Offload to background
        Task {
            do {
                // Task.detached creates a background task.
                // We await it, which suspends this MainActor task without blocking the thread.
                try await Task.detached(priority: .userInitiated) {
                    try await DeviceService.shared.sync(playlists: playlistDTOs, to: url, config: currentConfig, status: status)
                }.value

                // 3. Update UI on completion
                isSyncing = false
                statusManager.isBusy = false
                if let info = DeviceService.shared.getVolumeInfo(url: url) {
                    self.volumeInfo = info
                }

            } catch {
                isSyncing = false
                statusManager.isBusy = false
                statusManager.statusMessage = "Sync failed: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    DeviceManagerView()
        .environmentObject(StatusManager())
}
