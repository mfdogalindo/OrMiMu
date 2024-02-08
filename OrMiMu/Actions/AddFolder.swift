//
//  AddFolder.swift
//  OrMiMu
//
//  Created by Manuel Galindo on 7/02/24.
//

import Foundation
import AppKit

class AddFolder{
    
    func selectFolder() -> MusicPath? {
      var selectedFolderPath: String?
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = true
      panel.canChooseFiles = false

      let response = panel.runModal()
      if response == .OK {
        guard let url = panel.urls.first else {
            return nil;
        }
          selectedFolderPath = url.path;
          let components = selectedFolderPath!.components(separatedBy: "/");
          if let last = components.last {
              return MusicPath(name: last, path: selectedFolderPath!, mp3Files: scanFiles(folderPath: selectedFolderPath!));
          }
      }
      return nil;
    }
    
    func scanFiles(folderPath: String) -> [String] {
      let fileManager = FileManager.default
      let enumerator = fileManager.enumerator(atPath: folderPath)

      var mp3Files: [String] = []
      while let file = enumerator?.nextObject() as? String {
        if file.hasSuffix(".mp3") {
          mp3Files.append(file)
        }
      }
        return mp3Files;
    }

}

