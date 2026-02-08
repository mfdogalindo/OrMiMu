//
//  MusicPlayer.swift
//  OrMiMu
//
//  Created by Polarcito on 8/02/24.
//

import SwiftUI

struct MusicPlayer: View {
    @EnvironmentObject var audioPlayerManager: AudioPlayerManager
    @Binding var playableSong: URL?
    
    var body: some View {

        
        VStack(spacing: 4) {
            // Top: Song Info + Shuffle/Repeat
            HStack {
                // Left: Artwork
                if let artwork = audioPlayerManager.currentArtwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                        .cornerRadius(6)
                        .shadow(radius: 2)
                } else {
                    Image(systemName: "music.note")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)
                        .padding(15)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(6)
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .leading) {
                    Text(audioPlayerManager.currentTitle.isEmpty ? (playableSong?.deletingPathExtension().lastPathComponent ?? "Unknown Song") : audioPlayerManager.currentTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Text(audioPlayerManager.currentArtist.isEmpty ? "Unknown Artist" : audioPlayerManager.currentArtist)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { audioPlayerManager.toggleShuffle() }) {
                    Image(systemName: "shuffle")
                        .foregroundColor(audioPlayerManager.isShuffle ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)

                Button(action: { audioPlayerManager.previous() }) {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)

                Button(action: {
                    if audioPlayerManager.isPlaying {
                        audioPlayerManager.pause()
                    } else {
                        // Play current or resume
                         if let song = playableSong {
                             // Correctly using playAudio with current metadata if available, though manager handles resume internally now
                             audioPlayerManager.playAudio(from: song, title: audioPlayerManager.currentTitle, artist: audioPlayerManager.currentArtist)
                         }
                    }
                }) {
                    Image(systemName: audioPlayerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                }
                .buttonStyle(.plain)

                Button(action: { audioPlayerManager.next() }) {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)

            }
            .padding(.horizontal)

            // Middle: Scrubbing Slider
            HStack(spacing: 8) {
                Text(formatTime(audioPlayerManager.currentTime))
                    .font(.caption2)
                    .monospacedDigit()

                Slider(value: Binding(
                    get: { audioPlayerManager.currentTime },
                    set: { audioPlayerManager.seek(to: $0) }
                ), in: 0...(audioPlayerManager.duration > 0 ? audioPlayerManager.duration : 1))

                Text(formatTime(audioPlayerManager.duration))
                    .font(.caption2)
                    .monospacedDigit()
                
                
                Spacer()
                
                HStack {
                    Image(systemName: "speaker.fill")
                        .font(.caption)
                    Slider(value: Binding(
                        get: { audioPlayerManager.volume },
                        set: { audioPlayerManager.setVolume($0) }
                    ), in: 0...1)
                    .frame(width: 80)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption)
                }

                

            }
            .padding(.horizontal)

        }
        .padding(.vertical, 2)
        .background(Material.bar)
        .cornerRadius(12)
        .shadow(radius: 5)
        .onAppear {
            // Initial play handled by manager queue setting in parent or previous state
            if let song = playableSong, !audioPlayerManager.isPlaying {
                 // Try to resume or play. If it's a fresh load, we might not have metadata here unless passed.
                 // Ideally parent (MusicList) sets queue and plays.
                 // This block is mostly for if the view reappears.
            }
        }
        .onChange(of: audioPlayerManager.currentSongURL) { _, newURL in
            if let url = newURL {
                playableSong = url
            }
        }
    }

    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
