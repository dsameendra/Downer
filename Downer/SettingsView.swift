//
//  SettingsView.swift
//  Downer
//
//  Created by Dumindu Sameendra on 2025-04-17.
//

import AppKit
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {

    // persisted tool paths
    @AppStorage("ytDlpPath") private var ytDlpPath: String =
        "/opt/homebrew/bin/yt-dlp"
    @AppStorage("ffmpegPath") private var ffmpegPath: String =
        "/opt/homebrew/bin/ffmpeg"
    @AppStorage("ffprobePath") private var ffprobePath: String =
        "/opt/homebrew/bin/ffprobe"

    var body: some View {
        Form {
            Section("Global Shortcut") {
                KeyboardShortcuts.Recorder(for: .downloadShortcut)
            }

            Section("Tool Paths") {
                pathRow(label: "yt‑dlp", binding: $ytDlpPath)
                pathRow(label: "ffmpeg", binding: $ffmpegPath)
                pathRow(label: "ffprobe", binding: $ffprobePath)
            }
            .textFieldStyle(.roundedBorder)
        }
        .padding()
        .frame(width: 460)
        .tint(.red)
    }

    @ViewBuilder
    private func pathRow(label: String, binding: Binding<String>) -> some View {
        HStack {
            Text(label).frame(width: 70, alignment: .leading)
            TextField("", text: binding)
                .disabled(true)
            Spacer()
            Button("Browse…") { choosePath(for: binding) }
        }
    }

    private func choosePath(for binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose the executable file"
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                binding.wrappedValue = url.path
            }
        }
    }
}
