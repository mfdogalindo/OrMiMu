//
//  PlaylistListView.swift
//  OrMiMu
//
//  Created by Jules on 8/02/26.
//

import SwiftUI
import SwiftData

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
