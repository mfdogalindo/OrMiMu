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

    enum SidebarItem: Hashable, Identifiable {
        case library
        case playlists
        case download

        var id: Self { self }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: SidebarItem.library) {
                    Label("Library", systemImage: "music.note")
                }
                NavigationLink(value: SidebarItem.playlists) {
                    Label("Playlists", systemImage: "music.note.list")
                }
                NavigationLink(value: SidebarItem.download) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("OrMiMu")
            .toolbar {
                if selectedTab == .library {
                    ToolbarItem {
                        Button(action: addFolder) {
                            Label("Add Folder", systemImage: "folder.badge.plus")
                        }
                    }
                }
            }
        } detail: {
            switch selectedTab {
            case .library:
                MusicListView(songs: allSongs, playableSong: $playableSong)
                    .navigationTitle("Library")
            case .playlists:
                NavigationStack(path: $playlistPath) {
                    PlaylistListView(selectedPlaylist: $selectedPlaylist)
                        .navigationDestination(for: PlaylistItem.self) { playlist in
                            PlaylistDetailView(playlist: playlist, playableSong: $playableSong)
                        }
                }
            case .download:
                YouTubeDownloadView()
            case .none, .some:
                Text("Select an item")
            }
        }
        .overlay(alignment: .bottom) {
            if playableSong != nil {
                MusicPlayer(playableSong: $playableSong)
                    .frame(height: 80)
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
                    .padding()
            }
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        panel.begin { response in
            if response == .OK, let url = panel.url {
                let service = LibraryService(modelContext: modelContext)
                Task {
                    await service.scanFolder(at: url)
                }
            }
        }
    }
}

// MARK: - Playlist List View

struct PlaylistListView: View {
    @Query(sort: \PlaylistItem.name) private var playlists: [PlaylistItem]
    @Binding var selectedPlaylist: PlaylistItem?
    @Environment(\.modelContext) private var modelContext
    @State private var showSmartPlaylistSheet = false

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
                    Button("Delete") {
                        modelContext.delete(playlist)
                    }
                }
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem {
                Button(action: { showSmartPlaylistSheet = true }) {
                    Label("Smart Playlist", systemImage: "wand.and.stars")
                }
            }
            ToolbarItem {
                Button(action: addPlaylist) {
                    Label("Add Playlist", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showSmartPlaylistSheet) {
            SmartPlaylistView()
        }
    }

    private func addPlaylist() {
        let newPlaylist = PlaylistItem(name: "New Playlist")
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
        .navigationTitle($playlist.name)
        .toolbar {
            ToolbarItem {
                NavigationLink(destination: SyncView(songs: playlist.songs ?? [])) {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        }
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

// MARK: - YouTube Download View

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

// MARK: - Sync View

struct SyncView: View {
    let songs: [SongItem]

    @State private var destinationURL: URL?
    @State private var organizeByMetadata = true
    @State private var randomOrder = false
    @State private var isSyncing = false
    @State private var statusMessage = ""
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
            } else if !statusMessage.isEmpty {
                Text(statusMessage)
                    .foregroundStyle(statusMessage.starts(with: "Error") ? .red : .green)
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
                statusMessage = "Error selecting folder: \(error.localizedDescription)"
            }
        }
    }

    private func startSync() {
        guard let destination = destinationURL else { return }

        isSyncing = true
        statusMessage = "Syncing..."
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
                    statusMessage = "Sync Complete!"
                    progress = 1.0
                    isSyncing = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Error: \(error.localizedDescription)"
                    isSyncing = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [SongItem.self, PlaylistItem.self], inMemory: true)
}
