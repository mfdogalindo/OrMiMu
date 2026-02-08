//
//  SyncView.swift
//  OrMiMu
//
//  Created by Jules on 8/02/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct SyncView: View {
    let songs: [SongItem]

    @State private var destinationURL: URL?
    @State private var organizeByMetadata = true
    @State private var randomOrder = false
    @State private var isSyncing = false
    @State private var statusMessage = ""
    @State private var progress: Double = 0
    @State private var showFileImporter = false

    var body: some View {
        Form {
            Section("Destination") {
                HStack {
                    Text(destinationURL?.path ?? "Select a folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Browse...") {
                        showFileImporter = true
                    }
                }
            }

            Section("Options") {
                Toggle("Organize by Artist/Album", isOn: $organizeByMetadata)
                    .onChange(of: organizeByMetadata) { _, newValue in
                        if newValue { randomOrder = false }
                    }

                Toggle("Random Order (Flat Structure)", isOn: $randomOrder)
                    .disabled(organizeByMetadata)
                    .onChange(of: randomOrder) { _, newValue in
                        if newValue { organizeByMetadata = false }
                    }

                if randomOrder {
                    Text("Files will be renamed with a numerical prefix (e.g., 001_Song.mp3) to ensure random playback order on simple players.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if isSyncing {
                ProgressView("Syncing...")
            } else if !statusMessage.isEmpty {
                Text(statusMessage)
                    .foregroundStyle(statusMessage.starts(with: "Error") ? .red : .green)
            }

            Button("Start Sync") {
                startSync()
            }
            .disabled(destinationURL == nil || isSyncing)
        }
        .padding()
        .navigationTitle("Sync to Device")
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                destinationURL = urls.first
            case .failure(let error):
                statusMessage = "Error selecting folder: \(error.localizedDescription)"
            }
        }
    }

    private func startSync() {
        guard let destination = destinationURL else { return }

        isSyncing = true
        statusMessage = "Syncing..."
        progress = 0

        Task {
            do {
                try await SyncService.shared.sync(
                    songs: songs,
                    to: destination,
                    organize: organizeByMetadata,
                    randomOrder: randomOrder
                )

                await MainActor.run {
                    statusMessage = "Sync Complete!"
                    progress = 1.0
                    isSyncing = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Error: \(error.localizedDescription)"
                    isSyncing = false
                }
            }
        }
    }
}
