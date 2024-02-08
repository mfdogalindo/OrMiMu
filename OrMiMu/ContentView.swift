//
//  ContentView.swift
//  OrMiMu
//
//  Created by Manuel Galindo on 7/02/24.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [MusicPath]
    @State private var selected: MusicPath.ID?;

    private var addFolder: AddFolder = AddFolder.init();
    
    var body: some View {
        NavigationSplitView {
            List(items, selection: $selected) { item in
                Text(item.name)
                    .contextMenu { self.contextMenuFolderView(path: item) }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .toolbar {
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            MusicListView(paths: items, selected: $selected).id(selected)
        }
    }

    private func addItem() {
        withAnimation {
            let folder = addFolder.selectFolder();
            if(folder != nil){
                print(folder?.mp3Files as Any)
                modelContext.insert(folder!);
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
    

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
