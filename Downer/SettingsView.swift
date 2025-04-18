//
//  SettingsView.swift
//  Downer
//
//  Created by Dumindu Sameendra on 2025-04-17.
//

import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Global Shortcut") {
                KeyboardShortcuts.Recorder(for: .downloadShortcut)
            }
        }
        .padding()
        .frame(width: 350)
        .tint(.red)         // keeps the accent consistent here too
    }
}
