//
//  MiniDownloadView.swift
//  Downer
//
//  Created by Dumindu Sameendra on 2025-04-17.
//

import SwiftUI

struct MiniDownloadView: View {
    @AppStorage("downloadType")        private var downloadTypeRaw        = DownloadType.both.rawValue
    @AppStorage("selectedResolution")  private var selectedResolution      = "1080"
    @AppStorage("selectedVideoFormat") private var selectedVideoFormat     = "mp4"
    @AppStorage("selectedAudioQuality")private var selectedAudioQuality    = "320k"
    @AppStorage("selectedAudioFormat") private var selectedAudioFormat     = "mp3"

    @State private var videoURL      = ""
    @State private var downloadStatus = "Idle"
    @State private var isDownloading  = false
    @State private var currentProcess: Process?

    private var downloadType: DownloadType {
        DownloadType(rawValue: downloadTypeRaw) ?? .both
    }

    var body: some View {
            VStack(spacing: 16) {
                // URL
                TextField("YouTube URL", text: $videoURL)
                    .textFieldStyle(.roundedBorder)

                Button {
                    isDownloading ? stopDownload() : startDownload()
                } label: {
                    if isDownloading {
                        Label("Cancel", systemImage: "xmark.circle")
                    } else {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(videoURL.isEmpty && !isDownloading)
                .animation(.easeInOut, value: isDownloading)

                // Live status
                if isDownloading {
                    ProgressView()
                }
                Text(downloadStatus)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Divider()

                // Bring back the full window
                Button("Open Full App") { AppDelegate.shared.openFullApp() }
                    .buttonStyle(.bordered)

            }
            .padding(24)
            .frame(width: 320, height: 220)
            .tint(.red)                     
        }
    
    private func stopDownload() {
        currentProcess?.terminate()
        currentProcess = nil
        isDownloading = false
        downloadStatus = "Download cancelled."
    }

    private func startDownload() {
        guard !videoURL.isEmpty else { return }
        isDownloading = true
        downloadStatus = "Starting…"

        // same flags as main view:
        let formatOpt: String
        switch downloadType {
        case .audio:
            formatOpt = #"""
             -f bestaudio --extract-audio \
             --audio-format \#(selectedAudioFormat) \
             --audio-quality \#(selectedAudioQuality)
            """#
        case .video:
            formatOpt = #"""
             -f "bestvideo[height<=\#(selectedResolution)]" \
             --merge-output-format \#(selectedVideoFormat) \
             --no-audio
            """#
        case .both:
            formatOpt = #"""
             -f "bestvideo[height<=\#(selectedResolution)]+bestaudio" \
             --merge-output-format \#(selectedVideoFormat)
            """#
        }

        let path = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask)
            .first!.path.escaped()
        let cmd = "cd \(path) && /opt/homebrew/bin/yt-dlp \(formatOpt) \"\(videoURL.escaped())\""

        let proc = Process()
        proc.launchPath = "/bin/zsh"; proc.arguments = ["-c", cmd]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:" + (env["PATH"] ?? "")
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe; proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if let s = String(data:d, encoding:.utf8),
               !s.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                DispatchQueue.main.async { downloadStatus = s.trimmingCharacters(in:.whitespacesAndNewlines) }
            }
        }
        proc.terminationHandler = { p in
            DispatchQueue.main.async {
                isDownloading = false
                downloadStatus = p.terminationStatus == 0
                    ? "Done"
                    : "Error code \(p.terminationStatus)"
            }
        }

        currentProcess = proc
        do { try proc.run() } catch {
            downloadStatus = "Launch error: \(error.localizedDescription)"
            isDownloading = false
        }
    }
}
