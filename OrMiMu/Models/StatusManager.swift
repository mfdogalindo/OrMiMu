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
    @Published var progress: Double = 0.0
    @Published var statusDetail: String = ""
    var cancelAction: (() -> Void)? = nil

    func reset() {
        statusMessage = ""
        isBusy = false
        progress = 0.0
        statusDetail = ""
        cancelAction = nil
    }
}
