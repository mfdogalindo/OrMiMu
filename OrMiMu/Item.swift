//
//  Item.swift
//  OrMiMu
//
//  Created by Manuel Galindo on 7/02/24.
//

import Foundation
import SwiftData

@Model
final class Item {
    var folderName: String
    
    init(folderName: String) {
        self.folderName = folderName
    }
}
