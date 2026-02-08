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

    // Metadata Editing State
    @State private var songToEdit: SongItem?
    @State private var editingField: SongField?

    var sortedSongs: [SongItem] {
        return songs.sorted(using: sortOrder)
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
                Text(song.title)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        editSong(song, field: .title)
                    }
            }
            TableColumn("Artist", value: \.artist) { song in
                Text(song.artist)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        editSong(song, field: .artist)
                    }
            }
            TableColumn("Album", value: \.album) { song in
                Text(song.album)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        editSong(song, field: .album)
                    }
            }
            TableColumn("Genre", value: \.genre) { song in
                Text(song.genre)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        editSong(song, field: .genre)
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
        .onChange(of: sortOrder) { _, newOrder in
            saveSortOrder(newOrder)
        }
        .onAppear {
            updateSortOrder()
        }
        .contextMenu(forSelectionType: SongItem.ID.self) { selectedIDs in
            if !selectedIDs.isEmpty {
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
                            createNewPlaylist(with: selectedIDs)
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
    }

    private func editSong(_ song: SongItem, field: SongField) {
        editingField = field
        songToEdit = song
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

    private func createNewPlaylist(with songIDs: Set<SongItem.ID>) {
        let selectedSongs = sortedSongs.filter { songIDs.contains($0.id) }
        let newPlaylist = PlaylistItem(name: "New Playlist", songs: selectedSongs)
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
