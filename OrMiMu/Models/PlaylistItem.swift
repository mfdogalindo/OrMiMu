//
//  PlaylistItem.swift
//  OrMiMu
//
//  Created by Jules on 8/02/26.
//

import Foundation
import SwiftData

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
