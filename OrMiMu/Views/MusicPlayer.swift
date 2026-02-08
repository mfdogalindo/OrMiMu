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
    
    var body: some View{
        HStack{
            if let song = playableSong {
                Button(action: {
                    playableSong = nil
                    audioPlayerManager.stopAudio()
                }) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .padding(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 5))

                Button(action: {
                    audioPlayerManager.pause()
                }) {
                    Label((audioPlayerManager.isPlaying ? "Pause" : "Play"), systemImage: (audioPlayerManager.isPlaying ? "pause.fill" : "play.fill"))
                }
                .padding(EdgeInsets(top: 10, leading: 5, bottom: 10, trailing: 5))

                Spacer()

                Text("Playing: \(song.deletingPathExtension().lastPathComponent)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(EdgeInsets(top: 10, leading: 5, bottom: 10, trailing: 20))
            }

        }
        .onAppear{
            if let song = playableSong {
                audioPlayerManager.stopAudio()
                audioPlayerManager.playAudio(from: song)
            }
        }
        .onChange(of: playableSong) { _, newSong in
             if let song = newSong {
                 audioPlayerManager.stopAudio()
                 audioPlayerManager.playAudio(from: song)
             } else {
                 audioPlayerManager.stopAudio()
             }
        }
    }
}
