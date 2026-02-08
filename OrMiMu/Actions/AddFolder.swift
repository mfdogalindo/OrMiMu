//
//  AddFolder.swift
//  OrMiMu
//
//  Created by Manuel Galindo on 7/02/24.
//

import Foundation
import AppKit
import SwiftData
import AVFoundation

class AddFolder{
    
    func selectFolder() -> MusicPath? {
      var selectedFolderPath: String?
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = true
      panel.canChooseFiles = false

      let response = panel.runModal()
      if response == .OK {
        guard let url = panel.urls.first else {
            return nil;
        }
          selectedFolderPath = url.path;
          let components = selectedFolderPath!.components(separatedBy: "/");
          if let last = components.last {
              return MusicPath(name: last, path: selectedFolderPath!, mp3Files: scanFiles(folderPath: selectedFolderPath!));
          }
      }
      return nil;
    }
    
    func scanFiles(folderPath: String) -> [String] {
      let fileManager = FileManager.default
      let enumerator = fileManager.enumerator(atPath: folderPath)

      var mp3Files: [String] = []
      while let file = enumerator?.nextObject() as? String {
        if file.hasSuffix(".mp3") {
          mp3Files.append(file)
        }
      }
        return mp3Files;
    }

}

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
