//
//  PlaylistDetailView.swift
//  OrMiMu
//
//  Created by Jules on 8/02/26.
//

import SwiftUI
import SwiftData

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
