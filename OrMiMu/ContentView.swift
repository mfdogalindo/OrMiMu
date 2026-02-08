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

    @StateObject private var statusManager = StatusManager()
    @StateObject private var audioPlayerManager = AudioPlayerManager()

    enum SidebarItem: Hashable, Identifiable {
        case library
        case playlists
        case download

        var id: Self { self }

        var name: String {
            switch self {
            case .library: return "Library"
            case .playlists: return "Playlists"
            case .download: return "Download"
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

                Spacer()

                if selectedTab == .library {
                    Button(action: refreshMetadata) {
                        Label("Update Metadata", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(action: addFolder) {
                        Label("Add Folder", systemImage: "folder.badge.plus")
                    }
                } else if selectedTab == .playlists {
                     Button(action: { showSmartPlaylistSheet = true }) {
                        Label("Smart Playlist", systemImage: "wand.and.stars")
                    }
                    Button(action: addPlaylist) {
                        Label("Add Playlist", systemImage: "plus")
                    }
                }
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
                            }
                    }
                case .download:
                    YouTubeDownloadView()
                case .none, .some:
                    Text("Select an item")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Playing Controls
            if playableSong != nil {
                MusicPlayer(playableSong: $playableSong)
                    .frame(height: 80)
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
            .padding(8)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .navigationTitle(currentTitle)
        .environmentObject(statusManager)
        .environmentObject(audioPlayerManager)
        .sheet(isPresented: $showSmartPlaylistSheet) {
            SmartPlaylistView()
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

    private func addPlaylist() {
        let newPlaylist = PlaylistItem(name: "New Playlist")
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
        // Removed toolbar and state from here as they are moved to ContentView
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
    @EnvironmentObject var statusManager: StatusManager
    @State private var urlString: String = ""
    @State private var artist: String = ""
    @State private var album: String = ""
    @State private var genre: String = ""
    @State private var year: String = ""

    @State private var isDownloading = false
    // Removed local statusMessage state

    // Dependency Management
    @State private var isInstallingDependencies = false
    @State private var dependenciesInstalled = false

    // Preferences with local override support
    @AppStorage("downloadFormat") private var defaultFormat: String = "mp3"
    @AppStorage("downloadBitrate") private var defaultBitrate: String = "256"
    @State private var selectedFormat: String = "mp3"
    @State private var selectedBitrate: String = "256"

    let formats = ["mp3", "m4a", "flac", "wav"]
    let bitrates = ["128", "192", "256", "320"]

    var body: some View {
        Form {
            if !dependenciesInstalled {
                Section("Dependencies") {
                    if isInstallingDependencies {
                        ProgressView("Installing components (yt-dlp & ffmpeg)...")
                    } else {
                        Button("Install Dependencies") {
                            installDependencies()
                        }
                    }
                }
            }

            Section("Video URL") {
                TextField("https://...", text: $urlString)
            }

            Section("Settings") {
                Picker("Format", selection: $selectedFormat) {
                    ForEach(formats, id: \.self) { format in
                        Text(format.uppercased()).tag(format)
                    }
                }
                .pickerStyle(MenuPickerStyle())

                if selectedFormat == "mp3" || selectedFormat == "m4a" {
                    Picker("Bitrate (kbps)", selection: $selectedBitrate) {
                        ForEach(bitrates, id: \.self) { bitrate in
                            Text(bitrate).tag(bitrate)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }

            Section("Metadata Override (Optional)") {
                TextField("Artist", text: $artist)
                TextField("Album", text: $album)
                TextField("Genre", text: $genre)
                TextField("Year", text: $year)
            }

            if isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: statusManager.progress)
                    Text(statusManager.statusDetail.isEmpty ? "Downloading..." : statusManager.statusDetail)
                        .font(.caption)

                    Button("Stop Download") {
                        statusManager.cancelAction?()
                        isDownloading = false
                        statusManager.isBusy = false
                        statusManager.statusMessage = "Download stopped by user."
                        statusManager.reset()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button("Download") {
                    startDownload()
                }
                .disabled(urlString.isEmpty || !dependenciesInstalled)
            }
        }
        .padding()
        //.navigationTitle("YouTube Download") // Not needed in main content area
        .onAppear {
            checkDependencies()
            // Initialize with defaults if needed, or rely on state init
            selectedFormat = defaultFormat
            selectedBitrate = defaultBitrate
        }
    }

    private func checkDependencies() {
        dependenciesInstalled = DependencyManager.shared.isInstalled()
    }

    private func installDependencies() {
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

    private func startDownload() {
        guard let url = URL(string: urlString) else {
            statusManager.statusMessage = "Error: Invalid URL"
            return
        }

        isDownloading = true
        statusManager.isBusy = true
        statusManager.statusMessage = "Starting download..."
        statusManager.progress = 0.0
        statusManager.statusDetail = ""

        Task {
            do {
                let filePaths = try await YouTubeService.shared.download(
                    url: url,
                    format: selectedFormat,
                    bitrate: selectedBitrate,
                    statusManager: statusManager,
                    artist: nil,
                    album: nil,
                    genre: nil,
                    year: nil
                )

                var addedCount = 0
                for filePath in filePaths {
                    // Read current tags (YouTube defaults)
                    var currentTags = await MetadataService.readMetadata(url: URL(fileURLWithPath: filePath))

                    // Check if any overrides are provided
                    if !artist.isEmpty || !album.isEmpty || !genre.isEmpty || !year.isEmpty {
                        // Only override title if it's a single file download
                        let finalTitle = (filePaths.count == 1) ? currentTags.title : currentTags.title
                        let finalArtist = !artist.isEmpty ? artist : currentTags.artist
                        let finalAlbum = !album.isEmpty ? album : currentTags.album
                        let finalGenre = !genre.isEmpty ? genre : currentTags.genre
                        let finalYear = !year.isEmpty ? year : currentTags.year

                        // Apply override
                        try await MetadataService.updateMetadata(
                            filePath: filePath,
                            title: finalTitle,
                            artist: finalArtist,
                            album: finalAlbum,
                            genre: finalGenre,
                            year: finalYear
                        )

                        // Update local tags struct with overridden values for UI/DB
                        currentTags.artist = finalArtist
                        currentTags.album = finalAlbum
                        currentTags.genre = finalGenre
                        currentTags.year = finalYear
                    }

                    await MainActor.run {
                        addToLibrary(filePath: filePath, tags: currentTags)
                    }
                    addedCount += 1
                }

                await MainActor.run {
                    statusManager.statusMessage = "Success! Saved \(addedCount) songs."
                    isDownloading = false
                    statusManager.isBusy = false
                    statusManager.reset()
                    urlString = ""
                }
            } catch {
                await MainActor.run {
                    // Check if error is related to user cancellation if needed, but simple error display is fine
                    statusManager.statusMessage = "Error: \(error.localizedDescription)"
                    isDownloading = false
                    statusManager.isBusy = false
                    statusManager.reset()
                }
            }
        }
    }

    private func addToLibrary(filePath: String, tags: MetadataService.ExtractedTags) {
        let song = SongItem(
            title: tags.title.isEmpty ? URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent : tags.title,
            artist: tags.artist.isEmpty ? "Unknown Artist" : tags.artist,
            album: tags.album.isEmpty ? "Unknown Album" : tags.album,
            genre: tags.genre.isEmpty ? "Unknown Genre" : tags.genre,
            year: tags.year.isEmpty ? "Unknown Year" : tags.year,
            filePath: filePath,
            duration: 0 // Should ideally read duration from file
        )
        modelContext.insert(song)
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
