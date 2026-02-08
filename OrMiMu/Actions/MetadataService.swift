//
//  MetadataService.swift
//  OrMiMu
//
//  Created by Jules on 7/02/24.
//

import Foundation

enum MetadataError: Error {
    case ffmpegNotFound
    case fileNotFound
    case conversionFailed(String)
}

class MetadataService {
    static func updateMetadata(filePath: String, title: String, artist: String, album: String, genre: String) async throws {
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
        let arguments: [String] = [
            "-i", fileURL.path,
            "-metadata", "title=\(title)",
            "-metadata", "artist=\(artist)",
            "-metadata", "album=\(album)",
            "-metadata", "genre=\(genre)",
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
                    // replaceItemAt guarantees atomic replacement on compliant file systems
                    _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL, backupItemName: nil, options: .usingNewMetadataOnly)
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
