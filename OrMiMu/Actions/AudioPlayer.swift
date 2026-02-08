//
//  AudioPlayer.swift
//  OrMiMu
//
//  Created by Polarcito on 8/02/24.
//

import AVFoundation
import Combine

class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying: Bool = false
    @Published var duration: TimeInterval = 0
    @Published var currentTime: TimeInterval = 0
    @Published var currentSongTitle: String = "Not Playing"
    @Published var currentSongURL: URL?

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?

    override init() {
        super.init()
    }

    func playAudio(from url: URL) {
        // Stop current if any
        stopAudio()

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            isPlaying = true
            duration = audioPlayer?.duration ?? 0
            currentSongURL = url
            currentSongTitle = url.deletingPathExtension().lastPathComponent

            startTimer()
        } catch {
            print("Error playing audio: \(error.localizedDescription)")
            isPlaying = false
        }
    }

    func pauseAudio() {
        if isPlaying {
            audioPlayer?.pause()
            isPlaying = false
            stopTimer()
        } else {
            audioPlayer?.play()
            isPlaying = true
            startTimer()
        }
    }

    func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        currentSongTitle = "Not Playing"
        currentSongURL = nil
        stopTimer()
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer else { return }
            self.currentTime = player.currentTime
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        stopTimer()
        currentTime = 0
    }
}
