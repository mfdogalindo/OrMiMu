//
//  MusicList.swift
//  OrMiMu
//
//  Created by Manuel Galindo on 7/02/24.
//

import SwiftUI
import SwiftData

struct MusicListView: View {
    var songs: [SongItem]
    @Binding var playableSong: URL?
    var currentPlaylist: PlaylistItem? = nil

    @Query private var playlists: [PlaylistItem]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var audioPlayerManager: AudioPlayerManager

    @State private var selectedSongIDs = Set<SongItem.ID>()

    var body: some View {
        Table(songs, selection: $selectedSongIDs) {
            TableColumn("Title") { song in
                Text(song.title)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        playSong(song)
                    }
            }
            TableColumn("Artist") { song in
                Text(song.artist)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        playSong(song)
                    }
            }
            TableColumn("Album") { song in
                Text(song.album)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        playSong(song)
                    }
            }
            TableColumn("Genre") { song in
                Text(song.genre)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        playSong(song)
                    }
            }
            TableColumn("Length") { song in
                Text(formatDuration(song.duration))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        playSong(song)
                    }
            }
        }
        .contextMenu(forSelectionType: SongItem.ID.self) { selectedIDs in
            if !selectedIDs.isEmpty {
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
    }
    
    private func playSong(_ song: SongItem) {
        let queueItems = songs.map { (url: URL(fileURLWithPath: $0.filePath), title: $0.title, artist: $0.artist) }
        if let index = songs.firstIndex(where: { $0.id == song.id }) {
            audioPlayerManager.setQueue(queueItems, startAtIndex: index)
            playableSong = URL(fileURLWithPath: song.filePath)
        }
    }

    private func addToPlaylist(playlist: PlaylistItem, songIDs: Set<SongItem.ID>) {
        let selectedSongs = songs.filter { songIDs.contains($0.id) }
        if playlist.songs == nil { playlist.songs = [] }
        playlist.songs?.append(contentsOf: selectedSongs)
    }
    
    private func removeFromPlaylist(playlist: PlaylistItem, songIDs: Set<SongItem.ID>) {
        guard var existingSongs = playlist.songs else { return }
        playlist.songs = existingSongs.filter { !songIDs.contains($0.id) }
    }

    private func createNewPlaylist(with songIDs: Set<SongItem.ID>) {
        let selectedSongs = songs.filter { songIDs.contains($0.id) }
        let newPlaylist = PlaylistItem(name: "New Playlist", songs: selectedSongs)
        modelContext.insert(newPlaylist)
    }

    private func deleteFromLibrary(songIDs: Set<SongItem.ID>) {
        let songsToDelete = songs.filter { songIDs.contains($0.id) }
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
