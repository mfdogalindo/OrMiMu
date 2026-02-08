//
//  StatusManager.swift
//  OrMiMu
//
//  Created by Manuel Galindo on 08/02/26.
//

import SwiftUI

class StatusManager: ObservableObject {
    @Published var statusMessage: String = ""
    @Published var isBusy: Bool = false
}
