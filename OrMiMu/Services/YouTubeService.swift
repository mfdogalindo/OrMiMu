//
//  YouTubeService.swift
//  OrMiMu
//
//  Created by Jules on 8/02/26.
//

import Foundation

enum YouTubeError: Error {
    case toolNotFound
    case downloadFailed(String)
    case invalidURL
}

class YouTubeService {
    static let shared = YouTubeService()
    private var ytDlpPath: String?

    init() {
        self.ytDlpPath = findExecutable(name: "yt-dlp")
    }

    private func findExecutable(name: String) -> String? {
        // Try common locations first as 'which' might not be in path or sandboxed
        let commonPaths = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"]
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Try finding with 'which'
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                return path
            }
        } catch {
            print("Error finding \(name): \(error)")
        }

        return nil
    }

    func download(url: URL, title: String? = nil, artist: String? = nil, album: String? = nil, genre: String? = nil, year: String? = nil) async throws -> String {
        guard let ytDlpPath = ytDlpPath else {
            throw YouTubeError.toolNotFound
        }

        let outputFolder = FileManager.default.temporaryDirectory.appendingPathComponent("OrMiMu_Downloads")
        try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        let outputTemplate = outputFolder.path + "/%(title)s.%(ext)s"

        // Use --print filename to get the filename first?
        // Or just download.
        // We'll run download.

        var arguments = [
            "-x",
            "--audio-format", "mp3",
            "-o", outputTemplate,
            "--no-playlist", // Download single video by default unless it's a playlist URL?
            // If url is playlist, we might want to iterate. But for now assume single or let yt-dlp handle it.
            // If it's a playlist, this might download multiple files.
            url.absoluteString
        ]

        // Metadata overrides
        if let artist = artist, !artist.isEmpty {
            arguments.append(contentsOf: ["--metadata-from-title", "%(artist)s - %(title)s"]) // Just an example, hard to force artist tag without complex args
            // Better: use --parse-metadata
        }

        // Run process in background
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ytDlpPath)
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe // Capture error too

            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                // Parse output to find filename?
                // yt-dlp usually prints "[ExtractAudio] Destination: ..."
                // Simple hack: look for .mp3 in output lines
                if let line = output.components(separatedBy: .newlines).first(where: { $0.contains(".mp3") && $0.contains("Destination") }) {
                    // Extract path
                    // Example: [ExtractAudio] Destination: /path/to/file.mp3
                    let components = line.components(separatedBy: "Destination: ")
                    if components.count > 1 {
                        return components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                // Fallback: return folder and let caller scan?
                return outputFolder.path // This might be wrong if we need specific file.
            } else {
                throw YouTubeError.downloadFailed("Exit code \(process.terminationStatus): \(output)")
            }
        }.value
    }
}
