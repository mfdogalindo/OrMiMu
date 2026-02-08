//
//  SyncService.swift
//  OrMiMu
//
//  Created by Jules on 2/24/24.
//

import Foundation

enum SyncError: Error {
    case destinationNotWritable
    case copyFailed(String)
}

class SyncService {
    static let shared = SyncService()

    func sync(songs: [SongItem], to destination: URL, organize: Bool, randomOrder: Bool) async throws {
        let fileManager = FileManager.default

        // Ensure destination exists
        if !fileManager.fileExists(atPath: destination.path) {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        }

        // Shuffle if needed
        let songsToSync = randomOrder ? songs.shuffled() : songs

        for (index, song) in songsToSync.enumerated() {
            let sourceURL = URL(fileURLWithPath: song.filePath)
            guard fileManager.fileExists(atPath: song.filePath) else {
                print("Source file not found: \(song.filePath)")
                continue
            }

            var destURL = destination

            if organize {
                // Artist/Album structure
                let artist = song.artist.isEmpty ? "Unknown Artist" : song.artist
                let album = song.album.isEmpty ? "Unknown Album" : song.album

                destURL = destURL.appendingPathComponent(sanitize(artist))
                destURL = destURL.appendingPathComponent(sanitize(album))

                try? fileManager.createDirectory(at: destURL, withIntermediateDirectories: true)

                destURL = destURL.appendingPathComponent(sourceURL.lastPathComponent)
            } else {
                // Flat structure
                // If random order, prefix with index to force order on simple players
                if randomOrder {
                    let prefix = String(format: "%04d_", index + 1)
                    destURL = destURL.appendingPathComponent(prefix + sourceURL.lastPathComponent)
                } else {
                    destURL = destURL.appendingPathComponent(sourceURL.lastPathComponent)
                }
            }

            // Copy
            if fileManager.fileExists(atPath: destURL.path) {
                try? fileManager.removeItem(at: destURL)
            }

            try fileManager.copyItem(at: sourceURL, to: destURL)
        }
    }

    private func sanitize(_ string: String) -> String {
        // Remove illegal characters for filenames
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return string.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
}
