//
//  MainDownloadView.swift
//  Downer
//
//  Created by Dumindu Sameendra on 2025-04-17.
//

import AppKit
import SwiftUI

struct MainAppView: View {
    // user‑configurable tool paths
    @AppStorage("ytDlpPath") private var ytDlpPath: String =
        "/opt/homebrew/bin/yt-dlp"
    @AppStorage("ffmpegPath") private var ffmpegPath: String =
        "/opt/homebrew/bin/ffmpeg"
    @AppStorage("ffprobePath") private var ffprobePath: String =
        "/opt/homebrew/bin/ffprobe"

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
        .first!
        .path

    @State private var videoURL = ""
    @State private var downloadStatus = "Idle"
    @State private var isDownloading = false
    @State private var currentProcess: Process?

    private var downloadType: Binding<DownloadType> {
        Binding(
            get: { DownloadType(rawValue: downloadTypeRaw) ?? .both },
            set: { downloadTypeRaw = $0.rawValue }
        )
    }
    private var destinationFolder: URL {
        URL(fileURLWithPath: destinationFolderPath)
    }

    // MARK: – constants
    private let resolutionOptions = [
        "4320", "2160", "1080", "720", "480", "360", "240",
    ]
    private let videoFormatOptions = ["mp4", "mkv", "webm"]
    private let audioQualityOptions = ["256k", "192k", "128k", "64k"]
    private let audioFormatOptions = ["mp3", "m4a", "opus"]

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 24) {

                // URL
                TextField("Enter YouTube URL", text: $videoURL)
                    .textFieldStyle(.roundedBorder)
                
                Divider()

                // destination
                HStack {
                    Label(
                        destinationFolder.lastPathComponent,
                        systemImage: "folder"
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                    Spacer()
                    Button("Change…", action: selectFolder)
                }

                Divider()
                
                // type selector
                Picker("Download Type", selection: downloadType) {
                    ForEach(DownloadType.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Divider()
                
                // video options
                if downloadType.wrappedValue != .audio {
                    Grid(horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Text("Resolution")
                            Picker("", selection: $selectedResolution) {
                                ForEach(resolutionOptions, id: \.self) {
                                    Text("\($0)p")
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        GridRow {
                            Text("Container")
                            Picker("", selection: $selectedVideoFormat) {
                                ForEach(videoFormatOptions, id: \.self) {
                                    Text($0.uppercased())
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // audio options
                if downloadType.wrappedValue != .video {
                    Grid(horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Text("Quality")
                            Picker("", selection: $selectedAudioQuality) {
                                ForEach(audioQualityOptions, id: \.self) {
                                    Text($0)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        GridRow {
                            Text("Format")
                            Picker("", selection: $selectedAudioFormat) {
                                ForEach(audioFormatOptions, id: \.self) {
                                    Text($0.uppercased())
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(
                            "• **Your choices are remembered** – every setting you chose here will be your new defaults and will be used in the menubar pop-over app as well."
                        )
                        Text(
                            "• **Download / Cancel** – start downloading with one click and stop it at any time with the Cancel button."
                        )
                        Text(
                            "• **Hide & show** – closing this window hides it (and the Dock icon). Click the menu‑bar icon to bring it back."
                        )
                    }
                    .font(.callout)
                    .padding(.top, 2)
                } label: {
                    Text("Information")
                }
                
                Divider()
                
                VStack (alignment: .center, spacing: 24){
                    
                    // download / cancel button
                    Button {
                        isDownloading ? stopDownload() : startDownload()
                    } label: {
                        if isDownloading {
                            Label("Cancel Download", systemImage: "xmark.circle")
                        } else {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(videoURL.isEmpty && !isDownloading)
                    
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
                    
                    Text(downloadStatus).font(.subheadline)
                    
                    Spacer(minLength: 0)
                }
            }
            .padding(32)
            .animation(.easeInOut, value: downloadType.wrappedValue)
            
        }
        .frame(width: 450, height: 600)
        .tint(.red)  // accent colour for this window
    }

    // MARK: Actions
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                destinationFolderPath = url.path
            }
        }
    }

    private func stopDownload() {
        currentProcess?.terminate()
        currentProcess = nil
        isDownloading = false
        downloadStatus = "Download cancelled."
    }

    private func startDownload() {
        withAnimation { isDownloading = true }
        downloadStatus = "Starting download…"

        // validate all paths first
        guard FileManager.default.fileExists(atPath: destinationFolder.path)
        else {
            downloadStatus = "Destination folder not found."
            isDownloading = false
            return
        }
        guard FileManager.default.isExecutableFile(atPath: ytDlpPath) else {
            downloadStatus = "yt‑dlp not found.\nCheck Settings → Tool Paths."
            isDownloading = false
            return
        }
        guard FileManager.default.isExecutableFile(atPath: ffmpegPath),
            FileManager.default.isExecutableFile(atPath: ffprobePath)
        else {
            downloadStatus =
                "ffmpeg / ffprobe not found.\nCheck Settings → Tool Paths."
            isDownloading = false
            return
        }

        let formatOpt: String
        switch downloadType.wrappedValue {
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
        let ytCommand =
            "\"\(ytDlpPath.escaped())\" \(formatOpt) \"\(videoURL.escaped())\""
        let cmd = "cd \(workDir) && \(ytCommand)"

        let proc = Process()
        proc.launchPath = "/bin/zsh"
        proc.arguments = ["-c", cmd]

        var env = ProcessInfo.processInfo.environment
        let ffmpegDir = (ffmpegPath as NSString).deletingLastPathComponent
        env["PATH"] = "\(ffmpegDir):" + (env["PATH"] ?? "")
        env["FFMPEG"] = ffmpegPath
        env["FFPROBE"] = ffprobePath
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if let s = String(data: d, encoding: .utf8),
                !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                DispatchQueue.main.async {
                    downloadStatus = s.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                }
            }
        }
        proc.terminationHandler = { p in
            DispatchQueue.main.async {
                isDownloading = false
                downloadStatus =
                    p.terminationStatus == 0
                    ? "Download completed."
                    : "Download failed (code \(p.terminationStatus))."
            }
        }

        currentProcess = proc
        do { try proc.run() } catch {
            downloadStatus = "Error: \(error.localizedDescription)"
            isDownloading = false
        }
    }
}
