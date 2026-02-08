//
//  AudioPlayer.swift
//  OrMiMu
//
//  Created by Polarcito on 8/02/24.
//

import AVFoundation
import SwiftUI


class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    var audioPlayer: AVAudioPlayer?

    @Published var isPlaying: Bool = false
    @Published var duration: Double = 0
    @Published var currentTime: Double = 0
    @Published var volume: Double = 1.0
    @Published var isShuffle: Bool = false

    @Published var currentTitle: String = ""
    @Published var currentArtist: String = ""

    private var isPaused = false
    private var queue: [(url: URL, title: String, artist: String)] = []
    private var currentIndex: Int = -1
    private var timer: Timer?

    func playAudio(from url: URL, title: String = "", artist: String = "") {
        if let player = audioPlayer, player.url == url, isPaused {
            player.play()
            isPlaying = true
            isPaused = false
            startTimer()
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.volume = Float(volume)
            duration = audioPlayer?.duration ?? 0
            audioPlayer?.play()

            self.currentTitle = title.isEmpty ? url.deletingPathExtension().lastPathComponent : title
            self.currentArtist = artist.isEmpty ? "Unknown Artist" : artist

            isPlaying = true
            isPaused = false
            startTimer()
        } catch {
            print("Error at playing: \(error.localizedDescription)")
            isPlaying = false
        }
    }

    func setQueue(_ songs: [(url: URL, title: String, artist: String)], startAtIndex index: Int = 0) {
        self.queue = songs
        self.currentIndex = index
        if index >= 0 && index < songs.count {
            let song = songs[index]
            // Stop current if playing a different song
            if let url = audioPlayer?.url, url != song.url {
                stopAudio()
            }
            playAudio(from: song.url, title: song.title, artist: song.artist)
        }
    }

    func stopAudio() {
        audioPlayer?.stop()
        isPlaying = false
        isPaused = false
        stopTimer()
    }
    
    func pause(){
        if(!isPaused){
            audioPlayer?.pause()
            isPlaying = false
            stopTimer()
        }
        else{
            audioPlayer?.play()
            isPlaying = true
            startTimer()
        }
        isPaused = !isPaused
    }

    func next() {
        guard !queue.isEmpty else { return }

        if isShuffle {
            currentIndex = Int.random(in: 0..<queue.count)
        } else {
            currentIndex = (currentIndex + 1) % queue.count
        }
        let song = queue[currentIndex]
        // Reset player for new song
        audioPlayer = nil
        isPaused = false
        playAudio(from: song.url, title: song.title, artist: song.artist)
    }

    func previous() {
        guard !queue.isEmpty else { return }

        if (audioPlayer?.currentTime ?? 0) > 3.0 {
            audioPlayer?.currentTime = 0
            return
        }

        if isShuffle {
            currentIndex = Int.random(in: 0..<queue.count)
        } else {
            currentIndex = (currentIndex - 1 + queue.count) % queue.count
        }
        let song = queue[currentIndex]
        // Reset player for new song
        audioPlayer = nil
        isPaused = false
        playAudio(from: song.url, title: song.title, artist: song.artist)
    }

    func toggleShuffle() {
        isShuffle.toggle()
    }

    func seek(to time: Double) {
        audioPlayer?.currentTime = time
        currentTime = time
    }

    func setVolume(_ vol: Double) {
        volume = vol
        audioPlayer?.volume = Float(vol)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.currentTime = self?.audioPlayer?.currentTime ?? 0
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag {
            next()
        }
    }

    var currentSongURL: URL? {
        guard currentIndex >= 0 && currentIndex < queue.count else { return nil }
        return queue[currentIndex].url
    }
}
