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

#Preview {
    ContentView()
        .modelContainer(for: [SongItem.self, PlaylistItem.self], inMemory: true)
}
