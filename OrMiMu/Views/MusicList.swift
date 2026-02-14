//
//  MusicList.swift
//  OrMiMu
//
//  Created by Manuel Galindo on 7/02/24.
//

import SwiftUI
import SwiftData

enum SongField {
    case title, artist, album, genre

    var displayName: String {
        switch self {
        case .title: return "Title"
        case .artist: return "Artist"
        case .album: return "Album"
        case .genre: return "Genre"
        }
    }
}

// Wrapper for bulk edit sheet
struct BulkEditContext: Identifiable {
    let id = UUID()
    let songs: [SongItem]
}

struct MusicListView: View {
    var songs: [SongItem]
    @Binding var playableSong: URL?
    var currentPlaylist: PlaylistItem? = nil

    @Query private var playlists: [PlaylistItem]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var audioPlayerManager: AudioPlayerManager
    @EnvironmentObject var statusManager: StatusManager

    @State private var selectedSongIDs = Set<SongItem.ID>()

    // Sorting State
    @AppStorage("librarySortKey") private var sortKey: String = "title"
    @AppStorage("librarySortAscending") private var sortAscending: Bool = true
    @State private var sortOrder = [KeyPathComparator(\SongItem.title)]

    // Search State
    @State private var searchText = ""

    // Metadata Editing State
    @State private var songToEdit: SongItem?
    @State private var editingField: SongField?
    @State private var bulkEditContext: BulkEditContext?

    // New Playlist Creation
    @State private var showNewPlaylistAlert = false
    @State private var pendingPlaylistSongs: Set<SongItem.ID> = []

    var filteredSongs: [SongItem] {
        if searchText.isEmpty {
            return songs
        } else {
            return songs.filter { song in
                song.title.localizedCaseInsensitiveContains(searchText) ||
                song.artist.localizedCaseInsensitiveContains(searchText) ||
                song.album.localizedCaseInsensitiveContains(searchText) ||
                song.genre.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var sortedSongs: [SongItem] {
        return filteredSongs.sorted(using: sortOrder)
    }

    var body: some View {
        Table(sortedSongs, selection: $selectedSongIDs, sortOrder: $sortOrder) {
            TableColumn("") { song in
                if let playableSong = playableSong, playableSong.path == song.filePath {
                    Image(systemName: "waveform")
                        .foregroundStyle(.primary)
                        .onTapGesture {
                            playSong(song)
                        }
                } else {
                    Image(systemName: "play.fill")
                        .foregroundStyle(.secondary)
                        .onTapGesture {
                            playSong(song)
                        }
                }
            }
            .width(20)

            TableColumn("Title", value: \.title) { song in
                EditableCell(value: song.title) { newValue in
                    updateMetadata(song: song, field: .title, value: newValue)
                }
            }
            TableColumn("Artist", value: \.artist) { song in
                EditableCell(value: song.artist) { newValue in
                    updateMetadata(song: song, field: .artist, value: newValue)
                }
            }
            TableColumn("Album", value: \.album) { song in
                EditableCell(value: song.album) { newValue in
                    updateMetadata(song: song, field: .album, value: newValue)
                }
            }
            TableColumn("Genre", value: \.genre) { song in
                EditableCell(value: song.genre) { newValue in
                    updateMetadata(song: song, field: .genre, value: newValue)
                }
            }
            TableColumn("Format", value: \.fileExtension) { song in
                Text(song.fileExtension)
                    .contentShape(Rectangle())
            }
            TableColumn("Length", value: \.duration) { song in
                Text(formatDuration(song.duration))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        playSong(song)
                    }
            }
        }
        .searchable(text: $searchText, placement: .automatic, prompt: "Search Songs")
        .onChange(of: sortOrder) { _, newOrder in
            saveSortOrder(newOrder)
        }
        .onAppear {
            updateSortOrder()
        }
        .contextMenu(forSelectionType: SongItem.ID.self) { selectedIDs in
            if !selectedIDs.isEmpty {
                Button("Edit Metadata") {
                    let selectedSongs = sortedSongs.filter { selectedIDs.contains($0.id) }
                    if selectedSongs.count == 1, let first = selectedSongs.first {
                        editSong(first, field: .title) // Default to title for single edit sheet if needed
                    } else if selectedSongs.count > 1 {
                        bulkEditContext = BulkEditContext(songs: selectedSongs)
                    }
                }

                Divider()

                Button("Convert to Default Format") {
                    if let firstID = selectedIDs.first, let song = songs.first(where: { $0.id == firstID }) {
                        convertToDefaultFormat(song)
                    }
                }

                Button("Play") {
                    if let firstID = selectedIDs.first, let song = songs.first(where: { $0.id == firstID }) {
                        playSong(song)
                    }
                }
                Divider()

                if let currentPlaylist = currentPlaylist {
                    Button("Remove from Playlist") {
                        removeFromPlaylist(playlist: currentPlaylist, songIDs: selectedIDs)
                    }
                } else {
                    Menu("Add to Playlist") {
                        ForEach(playlists) { playlist in
                            Button(playlist.name) {
                                addToPlaylist(playlist: playlist, songIDs: selectedIDs)
                            }
                        }
                        Divider()
                        Button("New Playlist") {
                            pendingPlaylistSongs = selectedIDs
                            showNewPlaylistAlert = true
                        }
                    }
                }

                Divider()

                Button("Delete from Library") {
                    deleteFromLibrary(songIDs: selectedIDs)
                }
            }
        }
        .sheet(item: $songToEdit) { song in
            EditMetadataView(song: song, initialField: editingField)
        }
        .sheet(item: $bulkEditContext) { context in
            BulkEditMetadataView(songs: context.songs)
        }
        .playlistNameAlert(
            isPresented: $showNewPlaylistAlert,
            title: "New Playlist",
            message: "Enter a name for the new playlist.",
            initialName: "New Playlist"
        ) { name in
            createNewPlaylist(name: name, with: pendingPlaylistSongs)
            pendingPlaylistSongs = []
        }
    }

    private func editSong(_ song: SongItem, field: SongField) {
        editingField = field
        songToEdit = song
    }
    
    private func updateMetadata(song: SongItem, field: SongField, value: String) {
        // Optimistic UI update
        switch field {
        case .title: song.title = value
        case .artist: song.artist = value
        case .album: song.album = value
        case .genre: song.genre = value
        }

        Task {
            do {
                try await MetadataService.updateMetadata(
                    filePath: song.filePath,
                    title: song.title,
                    artist: song.artist,
                    album: song.album,
                    genre: song.genre,
                    year: song.year
                )
            } catch {
                print("Failed to save inline metadata: \(error)")
            }
        }
    }

    private func updateSortOrder() {
        let order: SortOrder = sortAscending ? .forward : .reverse
        switch sortKey {
        case "title": sortOrder = [KeyPathComparator(\SongItem.title, order: order)]
        case "artist": sortOrder = [KeyPathComparator(\SongItem.artist, order: order)]
        case "album": sortOrder = [KeyPathComparator(\SongItem.album, order: order)]
        case "genre": sortOrder = [KeyPathComparator(\SongItem.genre, order: order)]
        case "fileExtension": sortOrder = [KeyPathComparator(\SongItem.fileExtension, order: order)]
        case "duration": sortOrder = [KeyPathComparator(\SongItem.duration, order: order)]
        default: sortOrder = [KeyPathComparator(\SongItem.title, order: order)]
        }
    }

    private func saveSortOrder(_ newOrder: [KeyPathComparator<SongItem>]) {
        guard let first = newOrder.first else { return }
        sortAscending = first.order == .forward

        if first.keyPath == \SongItem.title { sortKey = "title" }
        else if first.keyPath == \SongItem.artist { sortKey = "artist" }
        else if first.keyPath == \SongItem.album { sortKey = "album" }
        else if first.keyPath == \SongItem.genre { sortKey = "genre" }
        else if first.keyPath == \SongItem.fileExtension { sortKey = "fileExtension" }
        else if first.keyPath == \SongItem.duration { sortKey = "duration" }
    }

    private func playSong(_ song: SongItem) {
        // Use sortedSongs for correct queue order
        let queueItems = sortedSongs.map { (url: URL(fileURLWithPath: $0.filePath), title: $0.title, artist: $0.artist) }
        if let index = sortedSongs.firstIndex(where: { $0.id == song.id }) {
            audioPlayerManager.setQueue(queueItems, startAtIndex: index)
            playableSong = URL(fileURLWithPath: song.filePath)
        }
    }

    private func addToPlaylist(playlist: PlaylistItem, songIDs: Set<SongItem.ID>) {
        let selectedSongs = sortedSongs.filter { songIDs.contains($0.id) }
        if playlist.songs == nil { playlist.songs = [] }
        playlist.songs?.append(contentsOf: selectedSongs)
    }
    
    private func removeFromPlaylist(playlist: PlaylistItem, songIDs: Set<SongItem.ID>) {
        guard var existingSongs = playlist.songs else { return }
        playlist.songs = existingSongs.filter { !songIDs.contains($0.id) }
    }

    private func createNewPlaylist(name: String, with songIDs: Set<SongItem.ID>) {
        let selectedSongs = sortedSongs.filter { songIDs.contains($0.id) }
        let newPlaylist = PlaylistItem(name: name, songs: selectedSongs)
        modelContext.insert(newPlaylist)
    }

    private func convertToDefaultFormat(_ song: SongItem) {
        let defaultFormat = UserDefaults.standard.string(forKey: "downloadFormat") ?? "mp3"
        let defaultBitrate = UserDefaults.standard.string(forKey: "downloadBitrate") ?? "256"

        // Prevent unnecessary conversion if already same format (rough check)
        if song.fileExtension.lowercased() == defaultFormat.lowercased() {
             // Maybe show alert? For now just skip.
             return
        }

        Task {
            do {
                try await ConversionService.convert(
                    song: song,
                    to: defaultFormat,
                    bitrate: defaultBitrate,
                    statusManager: statusManager
                )
                // Ensure model context saves changes to filePath
                try? modelContext.save()
            } catch {
                statusManager.statusMessage = "Conversion failed: \(error.localizedDescription)"
            }
        }
    }

    private func deleteFromLibrary(songIDs: Set<SongItem.ID>) {
        let songsToDelete = sortedSongs.filter { songIDs.contains($0.id) }
        for song in songsToDelete {
            modelContext.delete(song)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let seconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct EditableCell: View {
    var value: String
    var onCommit: (String) -> Void

    @State private var text: String = ""
    @State private var isEditing: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            if isEditing {
                TextField("", text: $text)
                    .textFieldStyle(.squareBorder)
                    .focused($isFocused)
                    .onSubmit {
                        onCommit(text)
                        isEditing = false
                    }
                    .onAppear {
                        text = value
                        isFocused = true
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused && isEditing {
                            // Optionally commit on focus lost, or just cancel.
                            // Standard behavior is often commit on click-away for table cells.
                            onCommit(text)
                            isEditing = false
                        }
                    }
            } else {
                Text(value)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        isEditing = true
                    }
            }
        }
    }
}

struct EditMetadataView: View {
    var song: SongItem
    var initialField: SongField?

    @Environment(\.dismiss) private var dismiss

    // Using separate state to allow cancel
    @State private var title: String = ""
    @State private var artist: String = ""
    @State private var album: String = ""
    @State private var genre: String = ""

    @FocusState private var focusedField: SongField?

    var body: some View {
        Form {
            TextField("Title", text: $title)
                .focused($focusedField, equals: .title)
            TextField("Artist", text: $artist)
                .focused($focusedField, equals: .artist)
            TextField("Album", text: $album)
                .focused($focusedField, equals: .album)
            TextField("Genre", text: $genre)
                .focused($focusedField, equals: .genre)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top)
        }
        .padding()
        .frame(minWidth: 300)
        .onAppear {
            title = song.title
            artist = song.artist
            album = song.album
            genre = song.genre
            focusedField = initialField
        }
    }

    private func save() {
        song.title = title
        song.artist = artist
        song.album = album
        song.genre = genre

        Task {
            do {
                try await MetadataService.updateMetadata(
                    filePath: song.filePath,
                    title: title,
                    artist: artist,
                    album: album,
                    genre: genre
                )
            } catch {
                print("Failed to save metadata to file: \(error)")
            }
        }
        dismiss()
    }
}

struct BulkEditMetadataView: View {
    var songs: [SongItem]
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var statusManager: StatusManager

    @State private var artist: String = ""
    @State private var album: String = ""
    @State private var genre: String = ""
    @State private var year: String = ""

    // Toggles to know if we should update this field
    @State private var updateArtist = false
    @State private var updateAlbum = false
    @State private var updateGenre = false
    @State private var updateYear = false

    var body: some View {
        Form {
            Section("Edit Metadata for \(songs.count) items") {
                HStack {
                    Toggle("", isOn: $updateArtist)
                        .labelsHidden()
                    TextField("Artist", text: $artist)
                        .disabled(!updateArtist)
                }
                HStack {
                    Toggle("", isOn: $updateAlbum)
                        .labelsHidden()
                    TextField("Album", text: $album)
                        .disabled(!updateAlbum)
                }
                HStack {
                    Toggle("", isOn: $updateGenre)
                        .labelsHidden()
                    TextField("Genre", text: $genre)
                        .disabled(!updateGenre)
                }
                 HStack {
                    Toggle("", isOn: $updateYear)
                        .labelsHidden()
                    TextField("Year", text: $year)
                        .disabled(!updateYear)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top)
        }
        .padding()
        .frame(minWidth: 400)
    }

    func save() {
        // Prepare data before task
        let newArtist = updateArtist ? artist : ""
        let newAlbum = updateAlbum ? album : ""
        let newGenre = updateGenre ? genre : ""
        let newYear = updateYear ? year : ""
        let shouldUpdateArtist = updateArtist
        let shouldUpdateAlbum = updateAlbum
        let shouldUpdateGenre = updateGenre
        let shouldUpdateYear = updateYear

        let totalCount = songs.count

        Task {
            await MainActor.run {
                statusManager.isBusy = true
                statusManager.progress = 0.0
                statusManager.statusMessage = "Updating metadata..."
            }

            for (index, song) in songs.enumerated() {
                // Determine current values inside loop as fallback
                let finalArtist = shouldUpdateArtist ? newArtist : song.artist
                let finalAlbum = shouldUpdateAlbum ? newAlbum : song.album
                let finalGenre = shouldUpdateGenre ? newGenre : song.genre
                let finalYear = shouldUpdateYear ? newYear : song.year

                // Only call update if something changed for this song
                if shouldUpdateArtist || shouldUpdateAlbum || shouldUpdateGenre || shouldUpdateYear {
                     try? await MetadataService.updateMetadata(
                        filePath: song.filePath,
                        title: song.title,
                        artist: finalArtist,
                        album: finalAlbum,
                        genre: finalGenre,
                        year: finalYear
                    )

                     // Optimistic UI updates must happen on main actor
                     await MainActor.run {
                         if shouldUpdateArtist { song.artist = finalArtist }
                         if shouldUpdateAlbum { song.album = finalAlbum }
                         if shouldUpdateGenre { song.genre = finalGenre }
                         if shouldUpdateYear { song.year = finalYear }

                         // Update progress
                         let progress = Double(index + 1) / Double(totalCount)
                         statusManager.progress = progress
                         statusManager.statusMessage = "Updating metadata (\(index + 1)/\(totalCount))..."
                     }
                }
            }

            await MainActor.run {
                statusManager.isBusy = false
                statusManager.statusMessage = "Metadata update complete."
                statusManager.progress = 0.0
            }
        }
        dismiss()
    }
}
