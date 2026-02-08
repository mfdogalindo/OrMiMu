//
//  LibraryService.swift
//  OrMiMu
//
//  Created by Jules on 8/02/26.
//

import Foundation
import SwiftData
import AVFoundation

class LibraryService {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func scanFolder(at url: URL) async {
        let fileManager = FileManager.default
        // Create an enumerator that skips hidden files
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return
        }

        while let fileURL = enumerator.nextObject() as? URL {
            if fileURL.pathExtension.lowercased() == "mp3" {
                // Check if exists logic could go here, but for now we insert.
                // Ideally we should check if filePath already exists in DB.

                let tags = await getID3Tag(url: fileURL)
                let duration = await getDuration(url: fileURL)

                let song = SongItem(
                    title: tags.title.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : tags.title,
                    artist: tags.artist.isEmpty ? "Unknown Artist" : tags.artist,
                    album: tags.album.isEmpty ? "Unknown Album" : tags.album,
                    genre: tags.genre.isEmpty ? "Unknown Genre" : tags.genre,
                    year: tags.year.isEmpty ? "Unknown Year" : tags.year,
                    filePath: fileURL.path,
                    duration: duration
                )

                modelContext.insert(song)
            }
        }
    }

    private func getDuration(url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            return CMTimeGetSeconds(duration)
        } catch {
            return 0
        }
    }

    struct ExtractedTags {
        var title: String = ""
        var artist: String = ""
        var album: String = ""
        var genre: String = ""
        var year: String = ""
    }

    private func getID3Tag(url: URL) async -> ExtractedTags {
        var newTag = ExtractedTags()
        let asset = AVURLAsset(url: url)
        do {
            let metadata = try await asset.load(.metadata)
            for item in metadata {
                guard let key = item.commonKey?.rawValue, let value = try await item.load(.value) else { continue }

                switch key {
                case "title":
                    newTag.title = "\(value)"
                case "artist":
                    newTag.artist = "\(value)"
                case "albumName":
                    newTag.album = "\(value)"
                case "type":
                    newTag.genre = "\(value)"
                case "creationDate":
                    newTag.year = "\(value)"
                default:
                    break
                }
            }
        } catch {
            print("Error reading metadata for \(url): \(error)")
        }
        return newTag
    }
}
