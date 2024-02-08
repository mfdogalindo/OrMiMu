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
