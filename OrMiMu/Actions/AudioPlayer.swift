//
//  AudioPlayer.swift
//  OrMiMu
//
//  Created by Polarcito on 8/02/24.
//

import AVFoundation
import SwiftUI
import MediaPlayer

class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    var audioPlayer: AVAudioPlayer?

    @Published var isPlaying: Bool = false
    @Published var duration: Double = 0
    @Published var currentTime: Double = 0
    @Published var volume: Double = 1.0
    @Published var isShuffle: Bool = false

    @Published var currentTitle: String = ""
    @Published var currentArtist: String = ""
    @Published var currentArtwork: NSImage?

    private var isPaused = false
    private var queue: [(url: URL, title: String, artist: String)] = []
    private var currentIndex: Int = -1
    private var timer: Timer?

    override init() {
        super.init()
        setupRemoteTransportControls()
    }

    func playAudio(from url: URL, title: String = "", artist: String = "") {
        if let player = audioPlayer, player.url == url, isPaused {
            player.play()
            isPlaying = true
            isPaused = false
            startTimer()
            updateNowPlayingInfo()
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
            self.currentArtwork = extractArtwork(from: url)

            isPlaying = true
            isPaused = false
            startTimer()
            updateNowPlayingInfo()
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
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        currentArtwork = nil
    }
    
    // Explicit play command for MPRemoteCommandCenter
    func play() {
        if isPaused {
            audioPlayer?.play()
            isPlaying = true
            isPaused = false
            startTimer()
            updateNowPlayingInfo()
        }
    }

    // Explicit pause command for MPRemoteCommandCenter
    func pause() {
        if !isPaused {
            audioPlayer?.pause()
            isPlaying = false
            isPaused = true
            stopTimer()
            updateNowPlayingInfo()
        }
    }

    func togglePlayPause(){
        if(!isPaused){
            pause()
        }
        else{
            play()
        }
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
            playAudio(from: queue[currentIndex].url, title: queue[currentIndex].title, artist: queue[currentIndex].artist)
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
        updateNowPlayingInfo()
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

    // MARK: - MPRemoteCommandCenter & MPNowPlayingInfoCenter

    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Play Command
        commandCenter.playCommand.addTarget { [unowned self] event in
            if self.audioPlayer != nil {
                self.play()
                return .success
            }
            return .commandFailed
        }

        // Pause Command
        commandCenter.pauseCommand.addTarget { [unowned self] event in
            if self.audioPlayer != nil {
                self.pause()
                return .success
            }
            return .commandFailed
        }

        // Toggle Play/Pause Command
        commandCenter.togglePlayPauseCommand.addTarget { [unowned self] event in
             if self.audioPlayer != nil {
                 self.togglePlayPause()
                 return .success
             }
             return .commandFailed
        }

        // Next Track Command
        commandCenter.nextTrackCommand.addTarget { [unowned self] event in
            self.next()
            return .success
        }

        // Previous Track Command
        commandCenter.previousTrackCommand.addTarget { [unowned self] event in
            self.previous()
            return .success
        }

        // Change Playback Position Command
        commandCenter.changePlaybackPositionCommand.addTarget { [unowned self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                self.seek(to: event.positionTime)
                return .success
            }
            return .commandFailed
        }
    }

    private func updateNowPlayingInfo() {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = currentTitle
        nowPlayingInfo[MPMediaItemPropertyArtist] = currentArtist
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = audioPlayer?.currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = audioPlayer?.isPlaying == true ? 1.0 : 0.0

        // Attempt to load artwork if available
        if let image = currentArtwork {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func extractArtwork(from url: URL) -> NSImage? {
        let asset = AVAsset(url: url)
        let metadata = asset.commonMetadata
        if let artworkItem = metadata.first(where: { $0.commonKey == .commonKeyArtwork }),
           let data = artworkItem.dataValue,
           let image = NSImage(data: data) {
            return image
        }
        return nil
    }
}
