//
//  MiniDownloadView.swift
//  Downer
//
//  Created by Dumindu Sameendra on 2025-04-17.
//

import AppKit
import SwiftUI

struct PopOverView: View {
    @AppStorage("downloadType") private var downloadTypeRaw = DownloadType.both
        .rawValue
    @AppStorage("selectedResolution") private var selectedResolution = "1080"
    @AppStorage("selectedVideoFormat") private var selectedVideoFormat = "mp4"
    @AppStorage("selectedAudioQuality") private var selectedAudioQuality =
        "320k"
    @AppStorage("selectedAudioFormat") private var selectedAudioFormat = "mp3"

    @AppStorage("destinationFolder") private var destinationFolderPath =
        FileManager
        .default
        .urls(for: .downloadsDirectory, in: .userDomainMask)
        .first!.path
    // user‑configurable tool paths
    @AppStorage("ytDlpPath") private var ytDlpPath: String =
        "/opt/homebrew/bin/yt-dlp"
    @AppStorage("ffmpegPath") private var ffmpegPath: String =
        "/opt/homebrew/bin/ffmpeg"
    @AppStorage("ffprobePath") private var ffprobePath: String =
        "/opt/homebrew/bin/ffprobe"

    @State private var videoURL = ""
    @State private var downloadStatus = "Idle"
    @State private var isDownloading = false
    @State private var currentProcess: Process?

    private var downloadType: DownloadType {
        DownloadType(rawValue: downloadTypeRaw) ?? .both
    }
    private var destinationFolder: URL {
        URL(fileURLWithPath: destinationFolderPath)
    }

    var body: some View {
        VStack(spacing: 14) {
            // URL Input
            TextField("Paste YouTube URL", text: $videoURL)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 1)
                .padding(.top, 10)

            // Action button
            Button {
                isDownloading ? stopDownload() : startDownload()
            } label: {
                Label(
                    isDownloading ? "Cancel" : "Download",
                    systemImage: isDownloading
                        ? "xmark.circle" : "arrow.down.circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(videoURL.isEmpty && !isDownloading)
            .animation(.easeInOut(duration: 0.2), value: isDownloading)

            ZStack {
                if isDownloading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .transition(.opacity)
                        .frame(height: 15)
                        .frame(alignment: .center)
                } else {
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                        .opacity(0.8)
                        .font(.system(size: 15, weight: .medium))
                        .frame(height: 15)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isDownloading)

            Text(downloadStatus)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 20)
                .frame(maxHeight: 20)

            Divider()

            // Toolbar button
            HStack {
                Button(action: AppDelegate.shared.openFullApp) {
                    Label("Open App", systemImage: "square.and.arrow.up")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
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

        // —— sanity checks —— //
        guard FileManager.default.fileExists(atPath: destinationFolder.path)
        else {
            downloadStatus = "Destination folder missing."
            return
        }
        guard FileManager.default.isExecutableFile(atPath: ytDlpPath) else {
            downloadStatus = "yt‑dlp not found.\nCheck Settings → Tool Paths."
            return
        }
        guard FileManager.default.isExecutableFile(atPath: ffmpegPath),
            FileManager.default.isExecutableFile(atPath: ffprobePath)
        else {
            downloadStatus =
                "ffmpeg / ffprobe missing.\nCheck Settings → Tool Paths."
            return
        }

        isDownloading = true
        downloadStatus = "Starting…"

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

        let workDir = destinationFolder.path.escaped()
        let cmd =
            "cd \(workDir) && \"\(ytDlpPath.escaped())\" \(formatOpt) \"\(videoURL.escaped())\""

        // —— launch —— //
        let proc = Process()
        proc.launchPath = "/bin/zsh"
        proc.arguments = ["-c", cmd]

        // expose tool paths
        let ffmpegDir = (ffmpegPath as NSString).deletingLastPathComponent
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(ffmpegDir):" + (env["PATH"] ?? "")
        env["FFMPEG"] = ffmpegPath
        env["FFPROBE"] = ffprobePath
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { h in
            if let s = String(data: h.availableData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !s.isEmpty
            {
                DispatchQueue.main.async { downloadStatus = s }
            }
        }
        proc.terminationHandler = { p in
            DispatchQueue.main.async {
                isDownloading = false
                downloadStatus =
                    p.terminationStatus == 0
                    ? "Done"
                    : "Error \(p.terminationStatus)"
            }
        }

        currentProcess = proc
        do { try proc.run() } catch {
            downloadStatus = "Launch error: \(error.localizedDescription)"
            isDownloading = false
        }
    }
}
