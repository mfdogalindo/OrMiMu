//
//  SettingsView.swift
//  OrMiMu
//
//  Created by Jules on 2/24/24.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("downloadFormat") private var downloadFormat: String = "mp3"
    @AppStorage("downloadBitrate") private var downloadBitrate: String = "256"
    @AppStorage("deleteAfterConversion") private var deleteAfterConversion: Bool = true

    let formats = ["mp3", "m4a", "flac", "wav"]
    let bitrates = ["128", "192", "256", "320"]

    var body: some View {
        Form {
            Section("Download Settings") {
                Picker("Audio Format", selection: $downloadFormat) {
                    ForEach(formats, id: \.self) { format in
                        Text(format.uppercased()).tag(format)
                    }
                }
                .pickerStyle(MenuPickerStyle())

                if downloadFormat == "mp3" || downloadFormat == "m4a" {
                    Picker("Bitrate (kbps)", selection: $downloadBitrate) {
                        ForEach(bitrates, id: \.self) { bitrate in
                            Text(bitrate).tag(bitrate)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }

            Section("Conversion") {
                Toggle("Delete original file after conversion", isOn: $deleteAfterConversion)
            }
        }
        .padding()
        .frame(width: 300, height: 150)
    }
}

#Preview {
    SettingsView()
}
