//
//  AudioPlayer.swift
//  OrMiMu
//
//  Created by Polarcito on 8/02/24.
//

import AVFoundation


class AudioPlayerManager {
    var audioPlayer: AVAudioPlayer?
    private var isPaused = false

    func playAudio(from url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            print("Error at playing: \(error.localizedDescription)")
        }
    }

    func stopAudio() {
        audioPlayer?.stop()
    }
    
    func pause(){
        if(!isPaused){
            audioPlayer?.pause()
        }
        else{
            audioPlayer?.play()
        }
        isPaused = !isPaused
    }
}
