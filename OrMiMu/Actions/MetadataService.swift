//
//  MetadataService.swift
//  OrMiMu
//
//  Created by Jules on 7/02/24.
//

import Foundation
import AVFoundation

enum MetadataError: Error {
    case ffmpegNotFound
    case fileNotFound
    case conversionFailed(String)
}

class MetadataService {
    struct ExtractedTags {
        var title: String = ""
        var artist: String = ""
        var album: String = ""
        var genre: String = ""
        var year: String = ""
    }

    static func readMetadata(url: URL) async -> ExtractedTags {
        var newTag = ExtractedTags()
        let asset = AVURLAsset(url: url)
        do {
            let metadata = try await asset.load(.metadata)
            for item in metadata {
                let value = try await item.load(.value)
                guard let value = value else { continue }

                var handled = false

                // Prioritize commonKey
                if let key = item.commonKey?.rawValue {
                    switch key {
                    case "title":
                        newTag.title = "\(value)"
                        handled = true
                    case "artist":
                        newTag.artist = "\(value)"
                        handled = true
                    case "albumName":
                        newTag.album = "\(value)"
                        handled = true
                    // REMOVED genre from commonKey to force fallback to identifier logic
                    // which prioritizes text-based identifiers over numeric ones.
                    case "creationDate":
                        newTag.year = "\(value)"
                        handled = true
                    default:
                        break
                    }
                }

                // Fallback to identifier for ID3 tags if not found via commonKey
                if !handled, let identifier = item.identifier?.rawValue {
                     // Genre: ID3 TCON, iTunes ©gen, iTunes gnre
                     // Prioritize text-based genres (©gen, TCON) over numeric/index based (gnre)
                     if identifier.contains("id3/TCON") || identifier.contains("genre") || identifier.contains("©gen") {
                         newTag.genre = "\(value)"
                     } else if newTag.genre.isEmpty && identifier.contains("gnre") {
                         newTag.genre = "\(value)"
                     }
                     // Title: ID3 TIT2, iTunes ©nam
                     if newTag.title.isEmpty && (identifier.contains("id3/TIT2") || identifier.contains("title") || identifier.contains("©nam")) {
                         newTag.title = "\(value)"
                     }
                     // Artist: ID3 TPE1, iTunes ©ART
                     if newTag.artist.isEmpty && (identifier.contains("id3/TPE1") || identifier.contains("artist") || identifier.contains("©ART")) {
                         newTag.artist = "\(value)"
                     }
                     // Album: ID3 TALB, iTunes ©alb
                     if newTag.album.isEmpty && (identifier.contains("id3/TALB") || identifier.contains("album") || identifier.contains("©alb")) {
                         newTag.album = "\(value)"
                     }
                }
            }
        } catch {
            print("Error reading metadata for \(url): \(error)")
        }
        return newTag
    }

    static func updateMetadata(filePath: String, title: String, artist: String, album: String, genre: String, year: String = "") async throws {
        // 1. Get ffmpeg path
        let ffmpegURL = DependencyManager.shared.ffmpegPath

        guard FileManager.default.fileExists(atPath: ffmpegURL.path) else {
             throw MetadataError.ffmpegNotFound
        }

        let fileURL = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MetadataError.fileNotFound
        }

        // 2. Create temp output path in the same directory to ensure atomic move/replacement support
        let tempURL = fileURL.deletingLastPathComponent().appendingPathComponent("temp_" + UUID().uuidString + "_" + fileURL.lastPathComponent)

        // 3. Construct arguments
        var arguments: [String] = [
            "-i", fileURL.path,
            "-metadata", "title=\(title)",
            "-metadata", "artist=\(artist)",
            "-metadata", "album=\(album)",
            "-metadata", "genre=\(genre)",
            "-metadata", "date=\(year)", // Use date for broad compatibility (ffmpeg maps to TYER/TDRC)
            "-c", "copy",
            "-id3v2_version", "3",
            "-y",
            tempURL.path
        ]

        // 4. Run Process in a detached task
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = ffmpegURL
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                // Success: Safely replace original with temp
                do {
                    // Use empty options for standard atomic replacement.
                    // DO NOT use .usingNewMetadataOnly as it preserves the old file content (data fork),
                    // effectively discarding the ID3 tag updates we just wrote to the temp file.
                    _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL, backupItemName: nil, options: [])
                } catch {
                    // If replacement fails, clean up temp
                    try? FileManager.default.removeItem(at: tempURL)
                    throw error
                }
            } else {
                // Failure
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                try? FileManager.default.removeItem(at: tempURL)
                throw MetadataError.conversionFailed(output)
            }
        }.value
    }
}
