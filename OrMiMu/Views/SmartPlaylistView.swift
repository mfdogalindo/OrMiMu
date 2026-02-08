//
//  SmartPlaylistView.swift
//  OrMiMu
//
//  Created by Jules on 8/02/26.
//

import SwiftUI
import SwiftData

struct SmartPlaylistView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = "Smart Playlist"
    @State private var selectedGenre: String = ""
    @State private var selectedArtist: String = ""

    @Query private var songs: [SongItem]
    @State private var uniqueGenres: [String] = []
    @State private var uniqueArtists: [String] = []

    var body: some View {
        Form {
            TextField("Playlist Name", text: $name)

            Section("Criteria") {
                Picker("Genre", selection: $selectedGenre) {
                    Text("Any").tag("")
                    ForEach(uniqueGenres, id: \.self) { genre in
                        Text(genre).tag(genre)
                    }
                }

                Picker("Artist", selection: $selectedArtist) {
                    Text("Any").tag("")
                    ForEach(uniqueArtists, id: \.self) { artist in
                        Text(artist).tag(artist)
                    }
                }
            }
            .onAppear {
                uniqueGenres = Array(Set(songs.map { $0.genre })).sorted()
                uniqueArtists = Array(Set(songs.map { $0.artist })).sorted()
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button("Create") {
                    createPlaylist()
                }
                .disabled(name.isEmpty)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top)
        }
        .padding()
        .frame(minWidth: 300, minHeight: 200)
    }

    private func createPlaylist() {
        let filteredSongs = songs.filter { song in
            let genreMatch = selectedGenre.isEmpty || song.genre == selectedGenre
            let artistMatch = selectedArtist.isEmpty || song.artist == selectedArtist
            return genreMatch && artistMatch
        }

        let criteriaDescription = [
            selectedGenre.isEmpty ? nil : "Genre: \(selectedGenre)",
            selectedArtist.isEmpty ? nil : "Artist: \(selectedArtist)"
        ].compactMap { $0 }.joined(separator: ", ")

        let playlist = PlaylistItem(
            name: name,
            isSmart: true,
            smartCriteria: criteriaDescription.isEmpty ? "All Songs" : criteriaDescription,
            songs: filteredSongs
        )

        modelContext.insert(playlist)
        dismiss()
    }
}
