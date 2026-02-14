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
    @State private var playableSong: URL? = nil
    @State private var selectedTab: SidebarItem? = .library
    
    // For Playlists navigation
    @State private var playlistPath = NavigationPath()
    @State private var selectedPlaylist: PlaylistItem?
    @State private var showSmartPlaylistSheet = false
    @State private var showNewPlaylistAlert = false
    @State private var showSyncSheet = false

    @StateObject private var statusManager = StatusManager()
    @StateObject private var audioPlayerManager = AudioPlayerManager()
    @StateObject private var downloadManager = DownloadManager()
    @StateObject private var deviceManagerContext = DeviceManagerContext()

    enum SidebarItem: Hashable, Identifiable {
        case library
        case playlists
        case download
        case external

        var id: Self { self }

        var name: String {
            switch self {
            case .library: return "Library"
            case .playlists: return "Playlists"
            case .download: return "Download"
            case .external: return "External Devices"
            }
        }
    }

    var currentTitle: String {
        return "OrMiMu - \(selectedTab?.name ?? "")"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header / Content Selector
            HStack(spacing: 20) {
                Button(action: { selectedTab = .library }) {
                    Label("Library", systemImage: "music.note")
                }
                .buttonStyle(HeaderButtonStyle(isSelected: selectedTab == .library))

                Button(action: { selectedTab = .playlists }) {
                    Label("Playlists", systemImage: "music.note.list")
                }
                .buttonStyle(HeaderButtonStyle(isSelected: selectedTab == .playlists))

                Button(action: { selectedTab = .download }) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(HeaderButtonStyle(isSelected: selectedTab == .download))

                Button(action: { selectedTab = .external }) {
                    Label("Devices", systemImage: "externaldrive")
                }
                .buttonStyle(HeaderButtonStyle(isSelected: selectedTab == .external))

                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            // Content
            ZStack {
                switch selectedTab {
                case .library:
                    MusicListView(songs: allSongs, playableSong: $playableSong)
                case .playlists:
                    NavigationStack(path: $playlistPath) {
                        PlaylistListView(selectedPlaylist: $selectedPlaylist)
                            .navigationDestination(for: PlaylistItem.self) { playlist in
                                PlaylistDetailView(playlist: playlist, playableSong: $playableSong)
                                    .onAppear {
                                        selectedPlaylist = playlist
                                    }
                            }
                    }
                case .download:
                    YouTubeDownloadView()
                case .external:
                    DeviceManagerView()
                case .none, .some:
                    Text("Select an item")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minWidth: 900, minHeight: 650)
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    if selectedTab == .library {
                        Button(action: refreshMetadata) {
                            Label("Update Metadata", systemImage: "arrow.triangle.2.circlepath")
                                .labelStyle(.titleAndIcon)
                        }
                        Button(action: addFolder) {
                            Label("Add Folder", systemImage: "folder.badge.plus")
                                .labelStyle(.titleAndIcon)
                        }
                    } else if selectedTab == .playlists {
                        if !playlistPath.isEmpty && selectedPlaylist != nil {
                            Button(action: { showSyncSheet = true }) {
                                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                        Button(action: { showSmartPlaylistSheet = true }) {
                            Label("Smart Playlist", systemImage: "wand.and.stars")
                                .labelStyle(.titleAndIcon)
                        }
                        Button(action: { showNewPlaylistAlert = true }) {
                            Label("Add Playlist", systemImage: "plus")
                                .labelStyle(.titleAndIcon)
                        }
                    } else {
                        // Maintain toolbar height consistency for other tabs
                        Spacer()
                    }
                }
            }

            // Playing Controls
            if playableSong != nil {
                MusicPlayer(playableSong: $playableSong)
                    .frame(height: 48)
                    .padding()
                    .background(Material.bar)
            }

            // Status Bar
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
        .navigationTitle(currentTitle)
        .environmentObject(statusManager)
        .environmentObject(audioPlayerManager)
        .environmentObject(downloadManager)
        .environmentObject(deviceManagerContext)
        .sheet(isPresented: $showSmartPlaylistSheet) {
            SmartPlaylistView()
        }
        .sheet(isPresented: $showSyncSheet) {
            SyncView(songs: selectedPlaylist?.songs ?? [])
        }
        .playlistNameAlert(
            isPresented: $showNewPlaylistAlert,
            title: "New Playlist",
            message: "Enter a name for the new playlist.",
            initialName: "New Playlist"
        ) { name in
            addPlaylist(name: name)
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

struct HeaderButtonStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(8)
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - Playlist List View

struct PlaylistListView: View {
    @Query(sort: \PlaylistItem.name) private var playlists: [PlaylistItem]
    @Binding var selectedPlaylist: PlaylistItem?
    @Environment(\.modelContext) private var modelContext

    @State private var playlistToRename: PlaylistItem?
    @State private var showRenameAlert = false

    var body: some View {
        List(selection: $selectedPlaylist) {
            ForEach(playlists) { playlist in
                NavigationLink(value: playlist) {
                    HStack {
                        Image(systemName: playlist.isSmart ? "gearshape" : "music.note.list")
                        Text(playlist.name)
                    }
                }
                .contextMenu {
                    Button("Rename") {
                        playlistToRename = playlist
                        showRenameAlert = true
                    }
                    Button("Delete") {
                        modelContext.delete(playlist)
                    }
                }
            }
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
        .navigationTitle($playlist.name)
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

// MARK: - YouTube Download View is now in Views/YouTubeDownloadView.swift

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
