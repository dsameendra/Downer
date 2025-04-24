//
//  PopOverView.swift
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
        "source"
    @AppStorage("selectedAudioFormat") private var selectedAudioFormat = "opus"

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

    @Environment(\.colorScheme) var colorScheme

    // MARK: - Theme
    private var glassBackground: some View {
        ZStack {
            (colorScheme == .dark
                ? Color.black.opacity(0.15) : Color.white.opacity(0.15))
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            // Background gradient
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

            VStack(spacing: 16) {
                // URL Input
                ZStack(alignment: .leading) {
                    glassBackground
                        .frame(height: 36)
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: 10,
                                style: .continuous
                            )
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    TextField("Paste URL", text: $videoURL)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .font(.subheadline)
                }

                // Download button
                Button(action: {
                    isDownloading ? stopDownload() : startDownload()
                }) {
                    HStack {
                        Image(
                            systemName: isDownloading
                                ? "xmark.circle.fill" : "arrow.down.circle.fill"
                        )
                        .font(.system(size: 14, weight: .medium))
                        Text(isDownloading ? "Cancel" : "Download")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        Group {
                            if isDownloading {
                                Color.gray.opacity(0.2)
                            } else {
                                brandGradient
                            }
                        }
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .foregroundColor(isDownloading ? .primary : .white)
                    .shadow(
                        color: Color.red.opacity(isDownloading ? 0 : 0.3),
                        radius: 4,
                        x: 0,
                        y: 2
                    )
                }
                .disabled(videoURL.isEmpty && !isDownloading)
                .buttonStyle(.plain)

                // Status indicator
                HStack(spacing: 10) {
                    if isDownloading {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "circle.fill")
                            .foregroundColor(
                                downloadStatus == "Idle"
                                    ? .green
                                    : downloadStatus.contains(
                                        "completed"
                                    ) ? .green : .orange
                            )
                            .font(.system(size: 8))
                    }

                    // Status text
                    Text(downloadStatus)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(height: 20)
                .animation(
                    .easeInOut(duration: 0.2),
                    value: isDownloading
                )
            }
            .padding(20)
        }
        .frame(width: 360, height: 180)
        .tint(.red)
    }

    private func numericAbr(_ quality: String) -> Int? {
        Int(quality.replacingOccurrences(of: "k", with: ""))
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

        // build yt‑dlp format string
        let audioFilter: String = {
            if selectedAudioQuality == "source" {
                return "bestaudio"
            }
            if let abr = numericAbr(selectedAudioQuality) {
                return "bestaudio[abr<=\(abr)][vcodec=none]"
            }
            return "bestaudio"
        }()

        let formatOpt: String
        switch downloadType {
        case .audio:
            var fmt = "-f \"\(audioFilter)\""

            // decide whether to transcode
            if selectedAudioFormat == "source" {
                // user wants untouched stream in its native container
                fmt += " --audio-format best"
            } else if selectedAudioFormat != "opus" {
                // transcode when requesting mp3 / m4a
                fmt += " --extract-audio --audio-format \(selectedAudioFormat)"
                if let abr = numericAbr(selectedAudioQuality), abr <= 160 {
                    fmt += " --audio-quality \(selectedAudioQuality)"
                }
            }
            formatOpt = fmt

        case .video:
            formatOpt = """
                -f "bestvideo[height<=\(selectedResolution)][acodec=none]" \
                --remux-video \(selectedVideoFormat)
                """

        case .both:
            formatOpt = """
                -f \"bestvideo[height<=\(selectedResolution)]+\(audioFilter)\" \\
                --merge-output-format \(selectedVideoFormat)
                """
        }

        let workDir = destinationFolder.path.escaped()
        let cmd =
            "cd \(workDir) && \"\(ytDlpPath.escaped())\" \(formatOpt) \"\(videoURL.escaped())\""

        isDownloading = true
        downloadStatus = "Starting…"

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

        // Revert to idle after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if !self.isDownloading {
                self.downloadStatus = "Idle"
            }
        }
    }

    private func stopDownload() {
        currentProcess?.terminate()
        currentProcess = nil
        isDownloading = false
        downloadStatus = "Download cancelled."
    }
}
