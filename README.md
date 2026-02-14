# OrMiMu - Organize My Music

OrMiMu is a robust macOS application designed to organize, manage, and synchronize your music library. It simplifies the process of downloading music, editing metadata, creating smart playlists, and syncing your collection to external devices like USB drives, SD cards, and Android phones.

## Features

### 🎵 Library Management
*   **Import & Scan:** Easily add folders to your library. OrMiMu scans for supported audio formats (MP3, M4A, FLAC, WAV, etc.) and avoids duplicates.
*   **Metadata Editing:**
    *   **Inline Editing:** Double-click any field (Title, Artist, Album, Genre) in the list to edit it directly.
    *   **Bulk Editing:** Select multiple songs to batch update Artist, Album, Genre, or Year.
    *   **Auto-Refresh:** Automatically re-reads metadata from files if changed externally.

### 📥 YouTube Downloader
*   **High Quality:** Download audio from YouTube videos and playlists.
*   **Metadata Embedding:** Automatically embeds Title, Artist, and Thumbnail into the downloaded file.
*   **Format Selection:** Choose your preferred format (MP3, M4A, FLAC) and bitrate.
*   **Powered by yt-dlp:** Utilizes the industry-standard `yt-dlp` tool for reliable downloads.

### 📋 Playlists
*   **Standard Playlists:** Create and manage custom playlists.
*   **Smart Playlists:** Create dynamic playlists based on criteria like Genre or Artist.
*   **Quick Actions:** Context menus to easily add songs to playlists or create new ones from a selection.

### 💾 External Device Manager (New!)
Sync your music to external storage devices with ease. Perfect for car stereos, MP3 players, or Android devices.
*   **Sync Logic:**
    *   **Simple Mode:** Flattens the folder structure (all songs in root). Optionally adds a random numerical prefix (`0001_Song.mp3`) for devices that play files in alphabetical order (dumb players).
    *   **Complex Mode:** Organizes files into folders based on Playlists (`/PlaylistName/Artist - Song.mp3`).
*   **Smart Sync:** Tracks copied files using a manifest (`ormimu_manifest.json`) to prevent duplicate copies and save time.
*   **Auto-Conversion:** Automatically converts songs to your target device's supported format (e.g., converts FLAC to MP3 on the fly).
*   **Storage Management:** Visual indicator of free space on the destination drive.
*   **CSV Export:** Generate a printable CSV list of all songs synced to the device.

## Installation

1.  **Requirements:** macOS 12.0+ (Monterey) or later.
2.  **Build from Source:**
    *   Clone the repository.
    *   Open `OrMiMu.xcodeproj` in Xcode.
    *   Build and Run.
3.  **Dependencies:**
    *   OrMiMu automatically handles the installation of `yt-dlp` and `ffmpeg` into its Application Support directory upon first use. No manual terminal setup required!

## License

This project is licensed under the **GNU General Public License v3.0 (GPLv3)**.

*   **Free Software:** You are free to use, copy, modify, and distribute this software.
*   **Copyleft:** If you modify this software and distribute it, your modifications must also be released under the GPLv3. This ensures the project remains open source and cannot be closed for proprietary commercialization.
*   See the `LICENSE` file for the full text.

---
*Created by [Your Name/Handle] - Preserving the spirit of open music management.*
