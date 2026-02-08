//
//  AudioPlayer.swift
//  OrMiMu
//
//  Created by Polarcito on 8/02/24.
//

import AVFoundation
import SwiftUI


class AudioPlayerManager: ObservableObject {
    var audioPlayer: AVAudioPlayer?
    @Published var isPlaying: Bool = false
    private var isPaused = false

    func playAudio(from url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            isPlaying = true
            isPaused = false
        } catch {
            print("Error at playing: \(error.localizedDescription)")
            isPlaying = false
        }
    }

    func stopAudio() {
        audioPlayer?.stop()
        isPlaying = false
        isPaused = false
    }
    
    func pause(){
        if(!isPaused){
            audioPlayer?.pause()
            isPlaying = false
        }
        else{
            audioPlayer?.play()
            isPlaying = true
        }
        isPaused = !isPaused
    }
}
