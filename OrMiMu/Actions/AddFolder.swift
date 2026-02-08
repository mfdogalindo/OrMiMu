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
            let ext = fileURL.pathExtension.lowercased()
            if ["mp3", "m4a", "wav", "opus", "flac"].contains(ext) {
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

enum YouTubeError: LocalizedError {
    case toolNotFound
    case downloadFailed(String)
    case invalidURL
    case dependencyInstallFailed(String)

    var errorDescription: String? {
        switch self {
        case .toolNotFound:
            return "yt-dlp or ffmpeg command line tool was not found. Please click 'Install Dependencies' to set it up automatically."
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .invalidURL:
            return "The provided URL is invalid."
        case .dependencyInstallFailed(let message):
            return "Failed to install dependencies: \(message)"
        }
    }
}

class DependencyManager {
    static let shared = DependencyManager()

    private let ytDlpURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
    // Using a reliable static build for ffmpeg
    private let ffmpegURL = URL(string: "https://evermeet.cx/ffmpeg/ffmpeg-122659-g8f57b04fe5.zip")!

    var binDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let binDir = appSupport.appendingPathComponent("OrMiMu/bin")
        try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        return binDir
    }

    var ytDlpPath: URL {
        return binDirectory.appendingPathComponent("yt-dlp_macos")
    }

    var ffmpegPath: URL {
        return binDirectory.appendingPathComponent("ffmpeg")
    }

    func isInstalled() -> Bool {
        return FileManager.default.fileExists(atPath: ytDlpPath.path) && FileManager.default.fileExists(atPath: ffmpegPath.path)
    }

    func install(progress: ((Double) -> Void)? = nil) async throws {
        // Create directory
        _ = binDirectory

        // 1. Download yt-dlp
        let (tempYtURL, ytResponse) = try await URLSession.shared.download(from: ytDlpURL)
        guard let httpYtResponse = ytResponse as? HTTPURLResponse, httpYtResponse.statusCode == 200 else {
            throw YouTubeError.dependencyInstallFailed("yt-dlp download failed")
        }

        if FileManager.default.fileExists(atPath: ytDlpPath.path) {
            try FileManager.default.removeItem(at: ytDlpPath)
        }
        try FileManager.default.moveItem(at: tempYtURL, to: ytDlpPath)

        // Make executable
        try setExecutable(path: ytDlpPath.path)
        progress?(0.5)

        // 2. Download ffmpeg
        let (tempFfmpegZipURL, ffmpegResponse) = try await URLSession.shared.download(from: ffmpegURL)
        guard let httpFfmpegResponse = ffmpegResponse as? HTTPURLResponse, httpFfmpegResponse.statusCode == 200 else {
            throw YouTubeError.dependencyInstallFailed("ffmpeg download failed")
        }

        // Unzip ffmpeg
        // We use /usr/bin/unzip because FileManager doesn't support unzipping directly
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", tempFfmpegZipURL.path, "-d", binDirectory.path]
        try process.run()
        process.waitUntilExit()

        // Make executable (just in case)
        if FileManager.default.fileExists(atPath: ffmpegPath.path) {
             try setExecutable(path: ffmpegPath.path)
        } else {
             // Sometimes zip contains a folder, but evermeet zip usually contains the binary at root
             // If not found, we might need to search
             throw YouTubeError.dependencyInstallFailed("ffmpeg binary not found after unzip")
        }

        progress?(1.0)
    }

    private func setExecutable(path: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+x", path]
        try process.run()
        process.waitUntilExit()
    }
}

class YouTubeService {
    static let shared = YouTubeService()

    private func getExecutablePath() -> String? {
        if DependencyManager.shared.isInstalled() {
            return DependencyManager.shared.ytDlpPath.path
        }
        // Fallback
        let commonPaths = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"]
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func getFFmpegDirectory() -> String? {
        if DependencyManager.shared.isInstalled() {
            return DependencyManager.shared.binDirectory.path
        }
        return nil
    }

    func download(url: URL, title: String? = nil, artist: String? = nil, album: String? = nil, genre: String? = nil, year: String? = nil, audioFormat: String = "mp3", audioQuality: String = "192K") async throws -> String {
        guard let ytDlpPath = getExecutablePath() else {
            throw YouTubeError.toolNotFound
        }

        let outputFolder = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first?.appendingPathComponent("OrMiMu") ?? FileManager.default.temporaryDirectory.appendingPathComponent("OrMiMu_Downloads")
        try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        let outputTemplate = outputFolder.path + "/%(title)s.%(ext)s"

        // Check if we have managed ffmpeg or system ffmpeg
        let ffmpegDir = getFFmpegDirectory()
        // If we don't have managed, check hasFFmpeg()
        let systemFFmpeg = hasFFmpeg()
        let hasAnyFFmpeg = ffmpegDir != nil || systemFFmpeg

        var arguments: [String] = []

        if hasAnyFFmpeg {
            arguments = [
                "-x",
                "--audio-format", audioFormat,
                "--audio-quality", audioQuality,
                "--embed-metadata", // Embed metadata (requires ffmpeg)
                "-o", outputTemplate,
                "--no-playlist",
                url.absoluteString
            ]
        } else {
            // Fallback
            print("FFmpeg not found. Downloading best audio format available.")
            arguments = [
                "-f", "bestaudio[ext=m4a]/bestaudio",
                "-o", outputTemplate,
                "--no-playlist",
                url.absoluteString
            ]
        }

        // Run process
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()

            process.executableURL = URL(fileURLWithPath: ytDlpPath)
            process.arguments = arguments

            // Set environment
            var env = ProcessInfo.processInfo.environment
            var pathEnv = env["PATH"] ?? ""

            // Add managed bin directory to PATH so yt-dlp can find ffmpeg
            if let managedBin = ffmpegDir {
                pathEnv = managedBin + ":" + pathEnv
            }
            // Add other common paths
            pathEnv += ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

            env["PATH"] = pathEnv
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                // Parse output to find filename
                if let line = output.components(separatedBy: .newlines).first(where: { ($0.contains(".mp3") || $0.contains(".m4a") || $0.contains(".opus") || $0.contains(".wav")) && $0.contains("Destination") }) {
                    let components = line.components(separatedBy: "Destination: ")
                    if components.count > 1 {
                        return components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                 // Try finding "has been downloaded"
                if let line = output.components(separatedBy: .newlines).first(where: { $0.contains("has been downloaded") }) {
                     if let match = output.components(separatedBy: .newlines).first(where: { $0.contains("[download]") && $0.contains("Destination:") }) {
                         let components = match.components(separatedBy: "Destination: ")
                         if components.count > 1 {
                             return components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                         }
                     }
                }
                return outputFolder.path
            } else {
                throw YouTubeError.downloadFailed("Exit code \(process.terminationStatus): \(output)")
            }
        }.value
    }

    private func hasFFmpeg() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffmpeg"]

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = env

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
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
