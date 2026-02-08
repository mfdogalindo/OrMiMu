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

// Global list of supported audio extensions for consistency
let kSupportedAudioExtensions = ["mp3", "m4a", "flac", "wav", "aac", "ogg", "aiff"]

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
        let ext = (file as NSString).pathExtension.lowercased()
        if kSupportedAudioExtensions.contains(ext) {
          mp3Files.append(file)
        }
      }
        return mp3Files;
    }

}

class LibraryService {
    let modelContext: ModelContext
    let statusManager: StatusManager?

    init(modelContext: ModelContext, statusManager: StatusManager? = nil) {
        self.modelContext = modelContext
        self.statusManager = statusManager
    }

    func scanFolder(at url: URL) async {
        await MainActor.run {
            statusManager?.statusMessage = "Scanning folder: \(url.lastPathComponent)..."
        }

        let fileManager = FileManager.default
        // Create an enumerator that skips hidden files
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            await MainActor.run {
                statusManager?.statusMessage = "Failed to access folder."
            }
            return
        }

        while let fileURL = enumerator.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            if kSupportedAudioExtensions.contains(ext) {
                await MainActor.run {
                    statusManager?.statusMessage = "Processing: \(fileURL.lastPathComponent)"
                }

                let filePath = fileURL.path
                let descriptor = FetchDescriptor<SongItem>(
                    predicate: #Predicate { $0.filePath == filePath }
                )

                // Check if already exists
                if let existingCount = try? modelContext.fetchCount(descriptor), existingCount > 0 {
                    await MainActor.run {
                        statusManager?.statusMessage = "Skipping duplicate: \(fileURL.lastPathComponent)"
                    }
                    continue
                }

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

        await MainActor.run {
            statusManager?.statusMessage = "Scan complete."
        }
    }

    func refreshMetadata(for songs: [SongItem]) async {
        let fileManager = FileManager.default
        var count = 0
        let total = songs.count

        for song in songs {
            count += 1
            if count % 10 == 0 || count == 1 {
                await MainActor.run {
                    statusManager?.statusMessage = "Updating metadata: \(count)/\(total)"
                }
            }

            let url = URL(fileURLWithPath: song.filePath)
            guard fileManager.fileExists(atPath: song.filePath) else { continue }

            let tags = await getID3Tag(url: url)
            let duration = await getDuration(url: url)

            // Update song properties
            song.title = tags.title.isEmpty ? url.deletingPathExtension().lastPathComponent : tags.title
            song.artist = tags.artist.isEmpty ? "Unknown Artist" : tags.artist
            song.album = tags.album.isEmpty ? "Unknown Album" : tags.album
            song.genre = tags.genre.isEmpty ? "Unknown Genre" : tags.genre
            song.year = tags.year.isEmpty ? "Unknown Year" : tags.year
            song.duration = duration
        }

        await MainActor.run {
            statusManager?.statusMessage = "Metadata update complete."
            // Save context if needed, though SwiftData usually autosaves
            try? modelContext.save()
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
                    case "genre":
                        newTag.genre = "\(value)"
                        handled = true
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
}

enum YouTubeError: LocalizedError {
    case toolNotFound
    case downloadFailed(String)
    case invalidURL
    case dependencyInstallFailed(String)

    var errorDescription: String? {
        switch self {
        case .toolNotFound:
            return "yt-dlp command line tool was not found. Please click 'Install Dependencies' to set it up automatically."
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

    // Updated to use the standalone macOS binary to avoid Python version issues
    private let ytDlpURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
    // Using a reliable source for static ffmpeg build
    private let ffmpegURL = URL(string: "https://evermeet.cx/ffmpeg/get/zip")!

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
        // Need both tools
        return FileManager.default.fileExists(atPath: ytDlpPath.path) &&
               FileManager.default.fileExists(atPath: ffmpegPath.path)
    }

    func install(progress: ((Double) -> Void)? = nil) async throws {
        // Create directory
        _ = binDirectory

        // 1. Install yt-dlp
        if FileManager.default.fileExists(atPath: ytDlpPath.path) {
             try? FileManager.default.removeItem(at: ytDlpPath)
        }

        let (tempURL, response) = try await URLSession.shared.download(from: ytDlpURL)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw YouTubeError.dependencyInstallFailed("yt-dlp download failed with status code: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        try FileManager.default.moveItem(at: tempURL, to: ytDlpPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+x", ytDlpPath.path]
        try process.run()
        process.waitUntilExit()

        progress?(0.5)

        // 2. Install ffmpeg
        if FileManager.default.fileExists(atPath: ffmpegPath.path) {
             try? FileManager.default.removeItem(at: ffmpegPath)
        }

        let (ffmpegTempURL, ffmpegResponse) = try await URLSession.shared.download(from: ffmpegURL)
        guard let ffHttpResponse = ffmpegResponse as? HTTPURLResponse, ffHttpResponse.statusCode == 200 else {
            throw YouTubeError.dependencyInstallFailed("ffmpeg download failed")
        }

        // Unzip logic
        // We can use /usr/bin/unzip
        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzipProcess.arguments = ["-o", ffmpegTempURL.path, "-d", binDirectory.path]
        try unzipProcess.run()
        unzipProcess.waitUntilExit()

        // Ensure ffmpeg is executable
        if FileManager.default.fileExists(atPath: ffmpegPath.path) {
            let chmodFF = Process()
            chmodFF.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmodFF.arguments = ["+x", ffmpegPath.path]
            try chmodFF.run()
            chmodFF.waitUntilExit()
        }

        progress?(1.0)
    }
}

class YouTubeService {
    static let shared = YouTubeService()

    private func getExecutablePath() -> String? {
        if DependencyManager.shared.isInstalled() {
            return DependencyManager.shared.ytDlpPath.path
        }
        // Fallback checks...
        let commonPaths = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"]
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    private func getFFmpegPath() -> String? {
        // Prefer managed
        if FileManager.default.fileExists(atPath: DependencyManager.shared.ffmpegPath.path) {
            return DependencyManager.shared.ffmpegPath.path
        }
        // Fallback
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffmpeg"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            return path
        }
        return nil
    }

    private func getPythonPath() -> String? {
        let versionedNames = ["python3.12", "python3.11", "python3.10"]
        let commonSearchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        for name in versionedNames {
            for path in commonSearchPaths {
                 let fullPath = path + "/" + name
                 if FileManager.default.fileExists(atPath: fullPath) { return fullPath }
            }
        }
        let commonPaths = ["/usr/bin/python3", "/usr/local/bin/python3", "/opt/homebrew/bin/python3"]
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    func download(url: URL, format: String, bitrate: String, title: String? = nil, artist: String? = nil, album: String? = nil, genre: String? = nil, year: String? = nil) async throws -> String {
        guard let ytDlpPath = getExecutablePath() else {
            throw YouTubeError.toolNotFound
        }

        let outputFolder = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first?.appendingPathComponent("OrMiMu") ?? FileManager.default.temporaryDirectory.appendingPathComponent("OrMiMu_Downloads")
        try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        let outputTemplate = outputFolder.path + "/%(title)s.%(ext)s"
        let ffmpegPath = getFFmpegPath()

        var arguments: [String] = [
            "-x", // Extract audio
            "--audio-format", format,
            "--audio-quality", "\(bitrate)K",
            "--add-metadata",
            "--embed-thumbnail",
            "-o", outputTemplate,
            "--no-playlist",
            url.absoluteString
        ]

        if let ffmpeg = ffmpegPath {
            // Need to insert ffmpeg-location before other args that might use it
             var newArgs: [String] = ["--ffmpeg-location", ffmpeg]
             newArgs.append(contentsOf: arguments)
             arguments = newArgs
        } else {
             print("Warning: FFmpeg not found. Conversion and metadata embedding may fail.")
        }

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()

            let isManagedBinary = ytDlpPath == DependencyManager.shared.ytDlpPath.path

            if isManagedBinary {
                process.executableURL = URL(fileURLWithPath: ytDlpPath)
                process.arguments = arguments
            } else {
                let pythonPath = YouTubeService.shared.getPythonPath()
                if let python = pythonPath {
                    process.executableURL = URL(fileURLWithPath: python)
                    var newArgs = [ytDlpPath]
                    newArgs.append(contentsOf: arguments)
                    process.arguments = newArgs
                } else {
                    process.executableURL = URL(fileURLWithPath: ytDlpPath)
                    process.arguments = arguments
                }
            }

            var env = ProcessInfo.processInfo.environment
            env["PATH"] = (env["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
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
                 if let line = output.components(separatedBy: .newlines).first(where: { $0.contains("Destination:") && ($0.contains(".mp3") || $0.contains(".\(format)")) }) {
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

                // Fallback for when conversion happens, sometimes "Destination" line is earlier for the temp file.
                // We should look for "[ExtractAudio] Destination: <final_file>"
                 if let line = output.components(separatedBy: .newlines).first(where: { $0.contains("[ExtractAudio] Destination:") }) {
                     let components = line.components(separatedBy: "Destination: ")
                     if components.count > 1 {
                         return components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                     }
                 }

                return outputFolder.path
            } else {
                throw YouTubeError.downloadFailed("Exit code \(process.terminationStatus): \(output)")
            }
        }.value
    }
}
