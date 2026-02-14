//
//  ContentView.swift
//  OrMiMu
//
//  Created by Manuel Galindo on 7/02/24.
//

import SwiftUI
import SwiftData
import AVFoundation

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allSongs: [SongItem]
    @Query(sort: \PlaylistItem.name) private var playlists: [PlaylistItem]

    @State private var playableSong: URL? = nil
    
    // Navigation State
    @State private var selectedItem: SidebarItem? = .library
    @State private var showSmartPlaylistSheet = false
    @State private var showNewPlaylistAlert = false
    @State private var showSyncSheet = false
    @State private var playlistToRename: PlaylistItem?
    @State private var showRenameAlert = false

    @StateObject private var statusManager = StatusManager()
    @StateObject private var audioPlayerManager = AudioPlayerManager()
    @StateObject private var downloadManager = DownloadManager()
    @StateObject private var deviceManagerContext = DeviceManagerContext()

    enum SidebarItem: Hashable, Identifiable {
        case library
        case download
        case external
        case playlist(PlaylistItem)

        var id: String {
            switch self {
            case .library: return "library"
            case .download: return "download"
            case .external: return "external"
            case .playlist(let item): return item.id.uuidString
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                Section("System") {
                    NavigationLink(value: SidebarItem.library) {
                        Label("Library", systemImage: "music.note")
                    }
                    NavigationLink(value: SidebarItem.download) {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }
                    NavigationLink(value: SidebarItem.external) {
                        Label("Devices", systemImage: "externaldrive")
                    }
                }
                Section("Playlists") {
                    ForEach(playlists) { playlist in
                        NavigationLink(value: SidebarItem.playlist(playlist)) {
                            Label(playlist.name, systemImage: playlist.isSmart ? "gearshape" : "music.note.list")
                        }
                        .contextMenu {
                            Button("Rename") {
                                playlistToRename = playlist
                                showRenameAlert = true
                            }
                            Button("Delete") {
                                modelContext.delete(playlist)
                                if case .playlist(let selected) = selectedItem, selected == playlist {
                                    selectedItem = nil
                                }
                            }
                        }
                    }
                }

            }
            .navigationTitle("OrMiMu")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: { showNewPlaylistAlert = true }) {
                        Label("Add Playlist", systemImage: "plus")
                    }
                    Button(action: { showSmartPlaylistSheet = true }) {
                        Label("Smart Playlist", systemImage: "wand.and.stars")
                    }
                }
            }
        } detail: {
            VStack(spacing: 0) {
                ZStack {
                    if let item = selectedItem {
                        switch item {
                        case .library:
                            MusicListView(songs: allSongs, playableSong: $playableSong)
                                .toolbar {
                                    ToolbarItemGroup(placement: .primaryAction) {
                                        Button(action: refreshMetadata) {
                                            Label("Update Metadata", systemImage: "arrow.triangle.2.circlepath")
                                                .labelStyle(.titleAndIcon)
                                        }
                                        Button(action: addFolder) {
                                            Label("Add Folder", systemImage: "folder.badge.plus")
                                                .labelStyle(.titleAndIcon)
                                        }
                                    }
                                }
                        case .playlist(let playlist):
                            PlaylistDetailView(playlist: playlist, playableSong: $playableSong)
                                .id(playlist.id) // Force refresh when switching playlists
                                .toolbar {
                                    ToolbarItemGroup(placement: .primaryAction) {
                                        Button(action: { showSyncSheet = true }) {
                                            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                                                .labelStyle(.titleAndIcon)
                                        }
                                        Button(action: {
                                            playlistToRename = playlist
                                            showRenameAlert = true
                                        }) {
                                            Label("Rename", systemImage: "pencil")
                                                .labelStyle(.titleAndIcon)
                                        }
                                        Button(role: .destructive, action: {
                                            modelContext.delete(playlist)
                                            selectedItem = nil
                                        }) {
                                            Label("Delete", systemImage: "trash")
                                                .labelStyle(.titleAndIcon)
                                        }
                                    }
                                }
                        case .download:
                            YouTubeDownloadView()
                        case .external:
                            DeviceManagerView()
                        }
                    } else {
                        Text("Select an item from the sidebar")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minWidth: 600, minHeight: 400)

                // Playing Controls - Persistent at bottom of detail view
                if playableSong != nil {
                    VStack(spacing: 0) {
                        Divider()
                        MusicPlayer(playableSong: $playableSong)
                            .frame(height: 48)
                            .padding()
                            .background(Material.bar)
                    }
                }

                // Status Bar - Persistent at bottom of detail view
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        if statusManager.isBusy {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.8)
                        }
                        Text(statusManager.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(height: 32)
                    .padding(.horizontal, 8)
                    .background(Color(NSColor.windowBackgroundColor))
                }
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        .environmentObject(statusManager)
        .environmentObject(audioPlayerManager)
        .environmentObject(downloadManager)
        .environmentObject(deviceManagerContext)
        .sheet(isPresented: $showSmartPlaylistSheet) {
            SmartPlaylistView()
        }
        .sheet(isPresented: $showSyncSheet) {
            if case .playlist(let playlist) = selectedItem {
                SyncView(songs: playlist.songs ?? [])
            }
        }
        .playlistNameAlert(
            isPresented: $showNewPlaylistAlert,
            title: "New Playlist",
            message: "Enter a name for the new playlist.",
            initialName: "New Playlist"
        ) { name in
            addPlaylist(name: name)
        }
        .playlistNameAlert(
            isPresented: $showRenameAlert,
            title: "Rename Playlist",
            message: "Enter a new name for the playlist.",
            initialName: playlistToRename?.name ?? ""
        ) { newName in
            if let playlist = playlistToRename {
                playlist.name = newName
            }
            playlistToRename = nil
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        panel.begin { response in
            if response == .OK, let url = panel.url {
                let service = LibraryService(modelContext: modelContext, statusManager: statusManager)
                Task {
                    await service.scanFolder(at: url)
                    await service.refreshMetadata(for: allSongs)
                }
            }
        }
    }

    private func refreshMetadata() {
        let service = LibraryService(modelContext: modelContext, statusManager: statusManager)
        Task {
            await service.refreshMetadata(for: allSongs)
        }
    }

    private func addPlaylist(name: String) {
        let newPlaylist = PlaylistItem(name: name)
        modelContext.insert(newPlaylist)
    }
}

// MARK: - Playlist Detail View

struct PlaylistDetailView: View {
    @Bindable var playlist: PlaylistItem
    @Binding var playableSong: URL?

    var body: some View {
        VStack {
            if let songs = playlist.songs, !songs.isEmpty {
                MusicListView(songs: songs, playableSong: $playableSong, currentPlaylist: playlist)
            } else {
                VStack {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("Playlist is Empty")
                        .font(.title2)
                        .bold()
                    Text("Add songs from the library.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(playlist.name)
    }
}

// MARK: - Smart Playlist View

struct SmartPlaylistView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = "Smart Playlist"
    @State private var selectedGenre: String = ""
    @State private var selectedArtist: String = ""

    @Query private var songs: [SongItem]
    @State private var uniqueGenres: [String] = []
    @State private var uniqueArtists: [String] = []

    var body: some View {
        Form {
            TextField("Playlist Name", text: $name)

            Section("Criteria") {
                Picker("Genre", selection: $selectedGenre) {
                    Text("Any").tag("")
                    ForEach(uniqueGenres, id: \.self) { genre in
                        Text(genre).tag(genre)
                    }
                }

                Picker("Artist", selection: $selectedArtist) {
                    Text("Any").tag("")
                    ForEach(uniqueArtists, id: \.self) { artist in
                        Text(artist).tag(artist)
                    }
                }
            }
            .onAppear {
                uniqueGenres = Array(Set(songs.map { $0.genre })).sorted()
                uniqueArtists = Array(Set(songs.map { $0.artist })).sorted()
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button("Create") {
                    createPlaylist()
                }
                .disabled(name.isEmpty)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top)
        }
        .padding()
        .frame(minWidth: 300, minHeight: 200)
    }

    private func createPlaylist() {
        let filteredSongs = songs.filter { song in
            let genreMatch = selectedGenre.isEmpty || song.genre == selectedGenre
            let artistMatch = selectedArtist.isEmpty || song.artist == selectedArtist
            return genreMatch && artistMatch
        }

        let criteriaDescription = [
            selectedGenre.isEmpty ? nil : "Genre: \(selectedGenre)",
            selectedArtist.isEmpty ? nil : "Artist: \(selectedArtist)"
        ].compactMap { $0 }.joined(separator: ", ")

        let playlist = PlaylistItem(
            name: name,
            isSmart: true,
            smartCriteria: criteriaDescription.isEmpty ? "All Songs" : criteriaDescription,
            songs: filteredSongs
        )

        modelContext.insert(playlist)
        dismiss()
    }
}

// MARK: - Sync View

struct SyncView: View {
    let songs: [SongItem]
    @EnvironmentObject var statusManager: StatusManager

    @State private var destinationURL: URL?
    @State private var organizeByMetadata = true
    @State private var randomOrder = false
    @State private var isSyncing = false
    // Removed local statusMessage
    @State private var progress: Double = 0
    @State private var showFileImporter = false

    var body: some View {
        Form {
            Section("Destination") {
                HStack {
                    Text(destinationURL?.path ?? "Select a folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Browse...") {
                        showFileImporter = true
                    }
                }
            }

            Section("Options") {
                Toggle("Organize by Artist/Album", isOn: $organizeByMetadata)
                    .onChange(of: organizeByMetadata) { _, newValue in
                        if newValue { randomOrder = false }
                    }

                Toggle("Random Order (Flat Structure)", isOn: $randomOrder)
                    .disabled(organizeByMetadata)
                    .onChange(of: randomOrder) { _, newValue in
                        if newValue { organizeByMetadata = false }
                    }

                if randomOrder {
                    Text("Files will be renamed with a numerical prefix (e.g., 001_Song.mp3) to ensure random playback order on simple players.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if isSyncing {
                ProgressView("Syncing...")
            }

            Button("Start Sync") {
                startSync()
            }
            .disabled(destinationURL == nil || isSyncing)
        }
        .padding()
        .navigationTitle("Sync to Device")
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                destinationURL = urls.first
            case .failure(let error):
                statusManager.statusMessage = "Error selecting folder: \(error.localizedDescription)"
            }
        }
    }

    private func startSync() {
        guard let destination = destinationURL else { return }

        isSyncing = true
        statusManager.isBusy = true
        statusManager.statusMessage = "Syncing..."
        progress = 0

        Task {
            do {
                try await SyncService.shared.sync(
                    songs: songs,
                    to: destination,
                    organize: organizeByMetadata,
                    randomOrder: randomOrder
                )

                await MainActor.run {
                    statusManager.statusMessage = "Sync Complete!"
                    progress = 1.0
                    isSyncing = false
                    statusManager.isBusy = false
                }
            } catch {
                await MainActor.run {
                    statusManager.statusMessage = "Error: \(error.localizedDescription)"
                    isSyncing = false
                    statusManager.isBusy = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [SongItem.self, PlaylistItem.self], inMemory: true)
}
