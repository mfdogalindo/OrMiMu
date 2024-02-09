//
//  MusicPlayer.swift
//  OrMiMu
//
//  Created by Polarcito on 8/02/24.
//

import SwiftUI

struct MusicPlayer: View {
    @State private var isPlaying : Bool = false
    @State private var isPaused : Bool = false
    @Binding var playableSong: URL?
    let audioPlayerManager = AudioPlayerManager()
    
    var body: some View{
        HStack{
            if(playableSong != nil){
                Button(action: {
                    isPlaying = false; playableSong = nil; isPaused = false; audioPlayerManager.stopAudio()
                }) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .padding(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 5))
                Button(action: {
                    isPaused = !isPaused;
                    audioPlayerManager.pause()
                }) {
                    Label((isPaused ? "Play":"Pause"), systemImage: (isPaused ? "play.fill":"pause.fill"))
                }
                .padding(EdgeInsets(top: 10, leading: 5, bottom: 10, trailing: 5))
                Spacer()
                Text("Playing: \(playableSong!)")
                    .padding(EdgeInsets(top: 10, leading: 5, bottom: 10, trailing: 20))
            }

        }
        .background(Color.black)
        .onAppear{
            isPlaying = true
            audioPlayerManager.stopAudio()
            audioPlayerManager.playAudio(from: playableSong!)
        }
    }
    
}
