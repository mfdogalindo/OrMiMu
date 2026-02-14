//
//  PlaylistAlerts.swift
//  OrMiMu
//
//  Created by Jules on 08/02/26.
//

import SwiftUI

struct PlaylistNameAlert: ViewModifier {
    @Binding var isPresented: Bool
    var title: String
    var message: String
    var initialName: String = ""
    var onConfirm: (String) -> Void

    @State private var text: String = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: $isPresented) {
                TextField("Name", text: $text)
                Button("Cancel", role: .cancel) { }
                Button("OK") {
                    if !text.isEmpty {
                        onConfirm(text)
                    }
                }
            } message: {
                Text(message)
            }
            .onChange(of: isPresented) { _, newValue in
                if newValue {
                    text = initialName
                }
            }
    }
}

extension View {
    func playlistNameAlert(isPresented: Binding<Bool>, title: String, message: String, initialName: String = "", onConfirm: @escaping (String) -> Void) -> some View {
        modifier(PlaylistNameAlert(isPresented: isPresented, title: title, message: message, initialName: initialName, onConfirm: onConfirm))
    }
}
