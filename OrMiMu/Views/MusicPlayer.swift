//
//  MusicPlayer.swift
//  OrMiMu
//
//  Created by Polarcito on 8/02/24.
//

import SwiftUI

struct MusicPlayer: View {
    @ObservedObject var audioManager: AudioPlayerManager
    
    var body: some View {
        VStack(spacing: 8) {
            // Title and Controls
            HStack {
                Text(audioManager.currentSongTitle)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Button(action: {
                    audioManager.stopAudio()
                }) {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                Button(action: {
                    if audioManager.isPlaying {
                        audioManager.pauseAudio()
                    } else {
                        // Resume logic: pauseAudio toggles state if song is loaded
                        // But if no song is loaded, we can't resume.
                        // However, currentSongURL is nil if stopped.
                        // Assuming pauseAudio handles resume correctly for paused state.
                        audioManager.pauseAudio()
                    }
                }) {
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.largeTitle)
                }
                .buttonStyle(.plain)
                .disabled(audioManager.currentSongURL == nil)
            }
            .padding(.horizontal)

            // Progress Bar
            if audioManager.currentSongURL != nil {
                HStack {
                    Text(formatTime(audioManager.currentTime))
                        .font(.caption)
                        .monospacedDigit()

                    Slider(value: Binding(
                        get: { audioManager.currentTime },
                        set: { newValue in audioManager.seek(to: newValue) }
                    ), in: 0...audioManager.duration)
                    .controlSize(.small)

                    Text(formatTime(audioManager.duration))
                        .font(.caption)
                        .monospacedDigit()
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 5)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
