//
//  SongModels.swift
//  OrMiMu
//
//  Created by Polarcito on 8/02/24.
//

import Foundation

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
