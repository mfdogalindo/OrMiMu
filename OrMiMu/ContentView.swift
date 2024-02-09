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
    @Query private var items: [MusicPath]
    @State private var selected: MusicPath.ID?
    @State private var playableSong: URL? = nil

    private var addFolder: AddFolder = AddFolder.init();
    
    var body: some View {
        NavigationSplitView {
            List(items, selection: $selected) { item in
                Text(item.name)
                    .contextMenu { self.contextMenuFolderView(path: item) }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
            .toolbar {
                ToolbarItem {
                    Button(action: addFolders) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            DetailView()
        }
    }
    
    private func DetailView() -> some View {
        VStack{
            MusicListView(paths: items, selected: $selected, playableSong: $playableSong)
                .id(selected)
            if(playableSong != nil){
                MusicPlayer(playableSong: $playableSong).id(playableSong)
            }
        }
    }

    
    private func contextMenuFolderView(path: MusicPath) -> some View {
        VStack {
            Button(action: {
                let fileURL = URL(fileURLWithPath: path.path)
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }) {
                Text("Show in Finder")
                Image(systemName: "folder")
            }
            Button(action: {
                modelContext.delete(path);
            }) {
                Text("Delete Item")
                Image(systemName: "trash")
            }
        }
    }


    private func addFolders() {
        withAnimation {
            let folder = addFolder.selectFolder();
            if(folder != nil){
                print(folder?.mp3Files as Any)
                modelContext.insert(folder!);
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
