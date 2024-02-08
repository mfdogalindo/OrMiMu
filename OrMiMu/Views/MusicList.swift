//
//  MusicList.swift
//  OrMiMu
//
//  Created by Manuel Galindo on 7/02/24.
//

import SwiftUI
import SwiftData
import AVFoundation

struct MusicListView: View {
    let paths: [MusicPath]
    @Binding var selected : MusicPath.ID?;
    @State var tableData: [Song] = []

    var body: some View{
        if let selectedPath = paths.first(where: {$0.id == selected}){
            Table(tableData){
                TableColumn("Path", value:  \.path)
                TableColumn("Archivo", value: \.name)
                TableColumn("Title", value: \.tags.title)
                TableColumn("Artist", value: \.tags.artist)
                TableColumn("Genre", value: \.tags.genre)
            }
            .task{
                tableData = []
                let newData = await getTags(folder: selectedPath)
                tableData = newData
            }
        }
        else{
            Text("Select an folder")
        }
    }
    
    func getID3Tag(url: URL) async -> Tags {

            var newTag : Tags = Tags(title: "", artist: "", genre: "");
            do{
                if let asset = AVAsset (url: url) as? AVURLAsset {
                    let metadata = try await asset.load(.metadata)
                   for item in metadata {
                        if let value =  try await item.load(.value) {
                            switch item.commonKey?.rawValue {
                            case "title":
                                newTag.title = "\(value)"
                            case "artist":
                                newTag.artist = "\(value)"
                            case "type":
                                  newTag.genre = "\(value)"
                            default:
                                break
                            }
                        }
                    }
                }
            }
            catch {
                print(error)
            }
        return newTag;
    }
    
    func getTags(folder: MusicPath) async -> [Song] {
        var result : [Song] = []
        for file in folder.mp3Files {
            let filePath = folder.path+"/"+file
            let url = URL(fileURLWithPath: filePath)
            let tags: Tags = await getID3Tag(url: url)
            result.append(Song(name: file, path: filePath, tags: tags))
        }
        return result
    }
    
}
