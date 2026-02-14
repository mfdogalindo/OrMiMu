//
//  DeviceManagerContext.swift
//  OrMiMu
//
//  Created by Jules on 08/02/26.
//

import SwiftUI
import SwiftData

class DeviceManagerContext: ObservableObject {
    @Published var deviceRoot: URL?
    @Published var config: DeviceConfig = DeviceConfig()
    @Published var volumeInfo: (total: Int64, free: Int64)?
    @Published var selectedPlaylists: Set<UUID> = []
    @Published var isSyncing: Bool = false
    @Published var targetFormat: String = "mp3"

    // Loads configuration and volume info for the current deviceRoot
    func refreshDeviceState() {
        guard let url = deviceRoot else { return }

        // Volume Info
        if let info = DeviceService.shared.getVolumeInfo(url: url) {
            self.volumeInfo = info
        }

        // Config
        if let loadedConfig = DeviceService.shared.loadConfig(from: url) {
            self.config = loadedConfig
            self.targetFormat = loadedConfig.supportedFormats.first ?? "mp3"
        } else {
            // If no config exists, create a default one and save it
            self.config = DeviceConfig()
            try? DeviceService.shared.saveConfig(self.config, to: url)
        }
    }

    func saveConfig() {
        guard let url = deviceRoot else { return }
        try? DeviceService.shared.saveConfig(config, to: url)
    }
}
