//
//  DeviceModels.swift
//  OrMiMu
//
//  Created by Jules on 08/02/26.
//

import Foundation

// MARK: - Configuration Model
struct DeviceConfig: Codable, Identifiable {
    var id: UUID
    var alias: String
    var description: String
    var supportedFormats: [String] // e.g., ["mp3", "aac"]
    var isSimpleDevice: Bool // True = Flat structure, False = Folders
    var randomizeCopy: Bool // True = Add random prefix to filenames (for simple devices)

    // Default initializer
    init(id: UUID = UUID(), alias: String = "My Device", description: String = "", supportedFormats: [String] = ["mp3"], isSimpleDevice: Bool = false, randomizeCopy: Bool = false) {
        self.id = id
        self.alias = alias
        self.description = description
        self.supportedFormats = supportedFormats
        self.isSimpleDevice = isSimpleDevice
        self.randomizeCopy = randomizeCopy
    }
}

// MARK: - Manifest Model
struct DeviceManifest: Codable {
    // Maps relative file path on device to source SongItem ID (UUID string)
    // Using string for key because file paths are strings
    var files: [String: String]

    init(files: [String: String] = [:]) {
        self.files = files
    }
}

// MARK: - Constants
struct DeviceConstants {
    static let configFileName = "ormimu_config.json"
    static let manifestFileName = "ormimu_manifest.json"
}

// MARK: - DTOs for Thread Safety
struct SongDTO: Identifiable, Sendable {
    let id: UUID
    let title: String
    let artist: String
    let album: String
    let filePath: String
}

struct PlaylistDTO: Identifiable, Sendable {
    let id: UUID
    let name: String
    let songs: [SongDTO]
}
