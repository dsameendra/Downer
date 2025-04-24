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

    @Environment(\.colorScheme) var colorScheme

    // MARK: – Theme from PopOverView
    private var glassBackground: some View {
        ZStack {
            (colorScheme == .dark
                ? Color.black.opacity(0.15) : Color.white.opacity(0.15))
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private var brandGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.red.opacity(0.9), Color.red.opacity(0.7),
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            // fix title and colors as soon as it's available to edit
            WindowAccessor { window in
                window.title = "Settings"
                window.titleVisibility = .visible
                window.titlebarAppearsTransparent = true
                window.isMovableByWindowBackground = true
                window.backgroundColor = .clear
            }
            
            LinearGradient(
                gradient: Gradient(colors: [
                    colorScheme == .dark
                        ? Color(white: 0.1) : Color(white: 0.95),
                    colorScheme == .dark ? Color.black : Color.white,
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                // Global Shortcut Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Global Shortcut")
                        .font(.headline)
                    glassBackground
                        .frame(height: 40)
                        .overlay(
                            KeyboardShortcuts.Recorder(for: .downloadShortcut)
                                .padding(.horizontal, 12)
                        )
                }

                // Tool Paths Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tool Paths")
                        .font(.headline)

                    pathRow(label: "yt-dlp", binding: $ytDlpPath)
                    pathRow(label: "ffmpeg", binding: $ffmpegPath)
                    pathRow(label: "ffprobe", binding: $ffprobePath)
                }
            }
            .padding(20)
        }
        .tint(.red)
        .frame(width: 400, height: 300)
    }

    @ViewBuilder
    private func pathRow(label: String, binding: Binding<String>) -> some View {
        ZStack {
            glassBackground
                .frame(height: 36)

            HStack(spacing: 8) {
                Text(label)
                    .font(.subheadline)
                    .frame(width: 70, alignment: .leading)

                TextField("", text: binding)
                    .textFieldStyle(.plain)
                    .disabled(true)

                Spacer()

                Button("Browse…") {
                    choosePath(for: binding)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(brandGradient)
                .clipShape(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .foregroundColor(.white)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
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
