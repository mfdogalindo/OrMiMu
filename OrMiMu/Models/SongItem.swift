//
//  SongItem.swift
//  OrMiMu
//
//  Created by Jules on 8/02/26.
//

import Foundation
import SwiftData

@Model
final class SongItem: Identifiable {
    var id: UUID
    var title: String
    var artist: String
    var album: String
    var genre: String
    var year: String
    var filePath: String
    var duration: Double
    var dateAdded: Date

    // Relationship to Playlist
    var playlists: [PlaylistItem]?

    init(id: UUID = UUID(), title: String, artist: String, album: String, genre: String, year: String, filePath: String, duration: Double, dateAdded: Date = Date()) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.year = year
        self.filePath = filePath
        self.duration = duration
        self.dateAdded = dateAdded
    }
}
