//
//  FilesModels.swift
//  OrMiMu
//
//  Created by Manuel Galindo on 7/02/24.
//

import Foundation
import SwiftData

@Model
final class MusicPath: Identifiable {
    var name: String
    var path: String
    var mp3Files: [String]

    init(name: String, path: String, mp3Files: [String]) {
        self.name = name
        self.path = path
        self.mp3Files = mp3Files
    }
}

// MARK: - Consolidated Models

struct Song: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let tags: Tags
    let url: URL
}

struct Tags {
    var title: String
    var artist: String
    var genre: String
}

@Model
final class SongItem: Identifiable {
    var id: UUID
    var title: String
    var artist: String
    var album: String
    var genre: String
    var year: String
    var filePath: String
    var sourceUrl: String? // Added for YouTube tracking
    var duration: Double
    var dateAdded: Date

    @Transient
    var fileExtension: String {
        return (filePath as NSString).pathExtension.uppercased()
    }

    // Relationship to Playlist
    var playlists: [PlaylistItem]?

    init(id: UUID = UUID(), title: String, artist: String, album: String, genre: String, year: String, filePath: String, sourceUrl: String? = nil, duration: Double, dateAdded: Date = Date()) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.year = year
        self.filePath = filePath
        self.sourceUrl = sourceUrl
        self.duration = duration
        self.dateAdded = dateAdded
    }
}

@Model
final class PlaylistItem: Identifiable {
    var id: UUID
    var name: String
    var creationDate: Date
    var isSmart: Bool
    var smartCriteria: String? // JSON string or comma separated for simplicity

    @Relationship(inverse: \SongItem.playlists)
    var songs: [SongItem]?

    init(id: UUID = UUID(), name: String, creationDate: Date = Date(), isSmart: Bool = false, smartCriteria: String? = nil, songs: [SongItem] = []) {
        self.id = id
        self.name = name
        self.creationDate = creationDate
        self.isSmart = isSmart
        self.smartCriteria = smartCriteria
        self.songs = songs
    }
}
