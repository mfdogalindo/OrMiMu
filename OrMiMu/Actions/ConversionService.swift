//
//  ConversionService.swift
//  OrMiMu
//
//  Created by Jules on 7/02/24.
//

import Foundation
import SwiftData

enum ConversionError: Error {
    case ffmpegNotFound
    case fileNotFound
    case conversionFailed(String)
}

class ConversionService {
    static func convert(song: SongItem, to format: String, bitrate: String, statusManager: StatusManager?) async throws {
        await MainActor.run {
            statusManager?.statusMessage = "Converting \"\(song.title)\" to \(format)..."
        }

        // 1. Get ffmpeg path
        let ffmpegURL = DependencyManager.shared.ffmpegPath

        guard FileManager.default.fileExists(atPath: ffmpegURL.path) else {
             throw ConversionError.ffmpegNotFound
        }

        let fileURL = URL(fileURLWithPath: song.filePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ConversionError.fileNotFound
        }

        // 2. Create output path
        let newExtension = format.lowercased()
        let directory = fileURL.deletingLastPathComponent()
        let filename = fileURL.deletingPathExtension().lastPathComponent

        // Ensure new filename is unique or handles overwrite properly
        var outputURL = directory.appendingPathComponent("\(filename).\(newExtension)")

        // If file exists and it's not the same file (e.g. converting Song.m4a to Song.mp3)
        // Check if we need to rename to avoid overwrite before conversion
        if FileManager.default.fileExists(atPath: outputURL.path) && outputURL != fileURL {
            outputURL = directory.appendingPathComponent("\(filename)_\(Int(Date().timeIntervalSince1970)).\(newExtension)")
        }

        // 3. Construct arguments
        // ffmpeg -i input -vn -ar 44100 -ac 2 -b:a 192k output.mp3
        var arguments: [String] = [
            "-i", fileURL.path,
            "-vn", // Disable video
            "-ar", "44100", // Sample rate
            "-ac", "2", // Channels
            "-b:a", "\(bitrate)k", // Bitrate
            "-id3v2_version", "3", // For MP3 compatibility
            "-y", // Overwrite output (we handle uniqueness above if needed)
            outputURL.path
        ]

        // 4. Run Process in detached task
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
                // Success

                // If the output file is different from the input file, check if we should delete original
                if fileURL != outputURL {
                    let deleteOriginal = UserDefaults.standard.bool(forKey: "deleteAfterConversion")
                    if deleteOriginal {
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                }

                // Update song item on MainActor
                await MainActor.run {
                    song.filePath = outputURL.path
                    statusManager?.statusMessage = "Conversion complete: \"\(song.title)\""
                }
            } else {
                // Failure
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                // Cleanup partial output if different from input
                if fileURL != outputURL {
                    try? FileManager.default.removeItem(at: outputURL)
                }
                throw ConversionError.conversionFailed(output)
            }
        }.value
    }
}
