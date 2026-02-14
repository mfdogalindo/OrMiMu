//
//  DeviceService.swift
//  OrMiMu
//
//  Created by Jules on 08/02/26.
//

import Foundation

class DeviceService {
    static let shared = DeviceService()

    // MARK: - Volume Info
    func getVolumeInfo(url: URL) -> (total: Int64, free: Int64)? {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer { if isSecurityScoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let values = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            if let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacity {
                return (Int64(total), Int64(free))
            }
        } catch {
            print("Error getting volume info: \(error)")
        }
        return nil
    }

    // MARK: - Configuration
    func loadConfig(from url: URL) -> DeviceConfig? {
        let fileURL = url.appendingPathComponent(DeviceConstants.configFileName)

        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer { if isSecurityScoped { url.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            let config = try JSONDecoder().decode(DeviceConfig.self, from: data)
            return config
        } catch {
            print("Error loading config: \(error)")
            return nil
        }
    }

    func saveConfig(_ config: DeviceConfig, to url: URL) throws {
        let fileURL = url.appendingPathComponent(DeviceConstants.configFileName)

        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer { if isSecurityScoped { url.stopAccessingSecurityScopedResource() } }

        let data = try JSONEncoder().encode(config)
        try data.write(to: fileURL)
    }

    // MARK: - Manifest
    func loadManifest(from url: URL) -> DeviceManifest {
        let fileURL = url.appendingPathComponent(DeviceConstants.manifestFileName)

        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer { if isSecurityScoped { url.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return DeviceManifest() }

        do {
            let data = try Data(contentsOf: fileURL)
            let manifest = try JSONDecoder().decode(DeviceManifest.self, from: data)
            return manifest
        } catch {
            print("Error loading manifest: \(error)")
            return DeviceManifest()
        }
    }

    func saveManifest(_ manifest: DeviceManifest, to url: URL) throws {
        let fileURL = url.appendingPathComponent(DeviceConstants.manifestFileName)

        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer { if isSecurityScoped { url.stopAccessingSecurityScopedResource() } }

        let data = try JSONEncoder().encode(manifest)
        try data.write(to: fileURL)
    }

    // MARK: - Sync Logic

    /// Syncs playlists to the device using DTOs
    func sync(playlists: [PlaylistDTO], to deviceRoot: URL, config: DeviceConfig, status: StatusManager) async throws {
        // Ensure security scope for the entire operation
        let isSecurityScoped = deviceRoot.startAccessingSecurityScopedResource()
        defer { if isSecurityScoped { deviceRoot.stopAccessingSecurityScopedResource() } }

        var manifest = loadManifest(from: deviceRoot)

        // 1. Handle Playlist Renaming (Complex Mode only)
        // If not simple mode, we use folders. We need to check if existing playlist IDs have new names.
        if !config.isSimpleDevice {
            for playlist in playlists {
                let playlistID = playlist.id.uuidString
                let currentName = playlist.name

                // If manifest tracks this ID but name differs
                if let oldFolderName = manifest.playlists[playlistID], oldFolderName != currentName {
                    // Rename folder
                    let oldURL = deviceRoot.appendingPathComponent(oldFolderName)
                    let newURL = deviceRoot.appendingPathComponent(currentName)

                    if FileManager.default.fileExists(atPath: oldURL.path) {
                        do {
                            // If target exists, merge? For now, assume rename if target absent.
                            // If target present, we might have a conflict or merge scenario.
                            // Simple rename:
                            try FileManager.default.moveItem(at: oldURL, to: newURL)
                            await MainActor.run { status.logOutput += "Renamed playlist folder: \(oldFolderName) -> \(currentName)\n" }

                            // Update Manifest paths that used old folder
                            // This is expensive O(N) over all files, but necessary to keep manifest valid
                            var newFiles: [String: String] = [:]
                            for (path, songID) in manifest.files {
                                if path.hasPrefix("\(oldFolderName)/") {
                                    let suffix = path.dropFirst(oldFolderName.count)
                                    let newPath = "\(currentName)\(suffix)"
                                    newFiles[newPath] = songID
                                } else {
                                    newFiles[path] = songID
                                }
                            }
                            manifest.files = newFiles
                        } catch {
                            await MainActor.run { status.logOutput += "Failed to rename playlist folder: \(error.localizedDescription)\n" }
                        }
                    }
                    // Update playlist map regardless
                    manifest.playlists[playlistID] = currentName
                } else if manifest.playlists[playlistID] == nil {
                    // New playlist tracking
                    manifest.playlists[playlistID] = currentName
                }
            }
        }

        // Build Reverse Lookup (ID -> Set<Path>)
        var existingPathsByID: [String: Set<String>] = [:]
        for (path, id) in manifest.files {
            existingPathsByID[id, default: []].insert(path)
        }

        // Items to process: (Song, PlaylistName?)
        var items: [(song: SongDTO, playlistName: String?)] = []

        if config.isSimpleDevice {
            // Flatten unique songs
            var seenIDs = Set<UUID>()
            for playlist in playlists {
                for song in playlist.songs {
                    if !seenIDs.contains(song.id) {
                        seenIDs.insert(song.id)
                        items.append((song, nil))
                    }
                }
            }
        } else {
            // Complex: Playlist folders
            for playlist in playlists {
                for song in playlist.songs {
                    items.append((song, playlist.name))
                }
            }
        }

        // 2. Iterate Items
        let total = items.count
        for (index, item) in items.enumerated() {
            let song = item.song
            let playlistName = item.playlistName

            // Check cancellation
            if Task.isCancelled {
                await MainActor.run { status.statusMessage = "Sync Cancelled" }
                return
            }
            // Also check status manager flag if used
            // But detached task relies on Task cancellation mostly.
            // If we want manual button cancel from UI:
            // StatusManager usually has a cancelAction closure that calls process.terminate() or task.cancel()
            // Here we check isBusy/cancelAction state if applicable, but standard way is Task.checkCancellation

            await MainActor.run {
                status.statusMessage = "Syncing \(index + 1) of \(total): \(song.title)"
                status.progress = Double(index) / Double(total)
            }

            // 3. Determine relative path
            var existingPath: String? = nil
            // In Simple Mode, reuse path to keep randomization stable
            if config.isSimpleDevice, let paths = existingPathsByID[song.id.uuidString], !paths.isEmpty {
                existingPath = paths.first
            }

            let relativePath = existingPath ?? generateRelativePath(for: song, playlistName: playlistName, config: config)

            // 4. Check Manifest & File Existence
            if let existingID = manifest.files[relativePath], existingID == song.id.uuidString {
                let destURL = deviceRoot.appendingPathComponent(relativePath)
                if FileManager.default.fileExists(atPath: destURL.path) {
                    // Skip copy
                    continue
                }
            }

            // 5. Check Free Space
            if index % 10 == 0 {
                if let info = getVolumeInfo(url: deviceRoot), info.free < 10_000_000 { // < 10MB
                    throw NSError(domain: "OrMiMu", code: 507, userInfo: [NSLocalizedDescriptionKey: "Not enough space on device."])
                }
            }

            // 6. Export
            do {
                try await exportSong(song: song, to: deviceRoot, relativePath: relativePath, config: config, status: status)

                // 7. Update Manifest
                manifest.files[relativePath] = song.id.uuidString
                try saveManifest(manifest, to: deviceRoot)

            } catch {
                await MainActor.run { status.logOutput += "Error syncing \(song.title): \(error.localizedDescription)\n" }
            }
        }

        await MainActor.run {
            status.progress = 1.0
            status.statusMessage = "Sync Complete"
        }
    }

    /// Generates the destination path
    private func generateRelativePath(for song: SongDTO, playlistName: String?, config: DeviceConfig) -> String {
        let ext = config.supportedFormats.first ?? "mp3"

        let safeTitle = song.title.replacingOccurrences(of: "/", with: "_")
        let safeArtist = song.artist.replacingOccurrences(of: "/", with: "_")

        let idSnippet = song.id.uuidString.prefix(4)
        let filename: String

        if safeArtist.isEmpty {
            filename = "\(safeTitle) [\(idSnippet)].\(ext)"
        } else {
            filename = "\(safeArtist) - \(safeTitle) [\(idSnippet)].\(ext)"
        }

        // Simple Mode (Flat)
        if config.isSimpleDevice {
            if config.randomizeCopy {
                let randomPrefix = String(format: "%04d", Int.random(in: 0...9999))
                return "\(randomPrefix)_\(filename)"
            } else {
                return filename
            }
        }

        // Complex Mode (Folders)
        if let plName = playlistName {
            let safePlaylist = plName.replacingOccurrences(of: "/", with: "_")
            return "\(safePlaylist)/\(filename)"
        } else {
            return filename
        }
    }

    /// Exports a single song
    private func exportSong(song: SongDTO, to deviceRoot: URL, relativePath: String, config: DeviceConfig, status: StatusManager) async throws {
        let sourceURL = URL(fileURLWithPath: song.filePath)
        let destURL = deviceRoot.appendingPathComponent(relativePath)
        let destFolder = destURL.deletingLastPathComponent()

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw NSError(domain: "OrMiMu", code: 404, userInfo: [NSLocalizedDescriptionKey: "Source file not found: \(song.filePath)"])
        }

        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)

        let targetFormat = config.supportedFormats.first ?? "mp3"
        let sourceExt = sourceURL.pathExtension.lowercased()

        let needsConversion = !config.supportedFormats.contains(sourceExt)

        if needsConversion {
            try await convertFile(source: sourceURL, destination: destURL, format: targetFormat)
        } else {
            let destExt = destURL.pathExtension.lowercased()
            if destExt != sourceExt {
                 try await convertFile(source: sourceURL, destination: destURL, format: targetFormat)
            } else {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
            }
        }
    }

    private func convertFile(source: URL, destination: URL, format: String) async throws {
        // Run blocking process in detached task
        try await Task.detached(priority: .userInitiated) {
            let ffmpegURL = DependencyManager.shared.ffmpegPath

            if source.pathExtension.lowercased() == format.lowercased() {
                 if FileManager.default.fileExists(atPath: destination.path) {
                     try FileManager.default.removeItem(at: destination)
                 }
                 try FileManager.default.copyItem(at: source, to: destination)
                 return
            }

            var arguments: [String] = [
                "-i", source.path,
                "-vn",
                "-ar", "44100",
                "-ac", "2",
                "-b:a", "192k",
                "-id3v2_version", "3",
                "-y",
                destination.path
            ]

            let process = Process()
            process.executableURL = ffmpegURL
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            // Prevent deadlock by reading output asynchronously
            pipe.fileHandleForReading.readabilityHandler = { handle in
                 let _ = handle.availableData // Discard output to prevent buffer fill
            }

            try process.run()
            process.waitUntilExit()

            // Clean up handler
            pipe.fileHandleForReading.readabilityHandler = nil

            if process.terminationStatus != 0 {
                // If failed, we might want the error output, but we discarded it.
                // Trade-off: Logging vs Safety.
                throw NSError(domain: "OrMiMu", code: 508, userInfo: [NSLocalizedDescriptionKey: "Conversion failed (ffmpeg error)"])
            }
        }.value
    }
}
