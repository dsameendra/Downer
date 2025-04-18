//
//  MainDownloadView.swift
//  Downer
//
//  Created by Dumindu Sameendra on 2025-04-17.
//


import SwiftUI
import AppKit

struct MainDownloadView: View {
    // Persisted settings
    @AppStorage("downloadType")        private var downloadTypeRaw        = DownloadType.both.rawValue
    @AppStorage("selectedResolution")  private var selectedResolution      = "1080"
    @AppStorage("selectedVideoFormat") private var selectedVideoFormat     = "mp4"
    @AppStorage("selectedAudioQuality")private var selectedAudioQuality    = "320k"
    @AppStorage("selectedAudioFormat") private var selectedAudioFormat     = "mp3"
    @AppStorage("destinationFolder") private var destinationFolderPath = FileManager
        .default
        .urls(for: .downloadsDirectory, in: .userDomainMask)
        .first!
        .path
    
    // Transient UI state
    @State private var videoURL      = ""
    @State private var downloadStatus = "Idle"
    @State private var isDownloading  = false
    @State private var currentProcess: Process?

    // Bindings & helpers
    
    private var downloadType: Binding<DownloadType> {
        Binding(
            get: { DownloadType(rawValue: downloadTypeRaw) ?? .both },
            set: { downloadTypeRaw = $0.rawValue }
        )
    }
    private var destinationFolder: URL { URL(fileURLWithPath: destinationFolderPath) }

    // MARK: – constants
    private let resolutionOptions   = ["4320","2160","1080","720","480","360","240"]
    private let videoFormatOptions  = ["mp4","mkv","webm"]
    private let audioQualityOptions = ["320k","256k","192k","128k","64k"]
    private let audioFormatOptions  = ["mp3","m4a","opus"]

    var body: some View {
        ScrollView {                    // smoother resize & avoids clipped pop‑over
            VStack(alignment: .center, spacing: 24) {

                // URL
                TextField("Enter YouTube URL", text: $videoURL)
                    .textFieldStyle(.roundedBorder)

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• **Your choices are remembered** – every setting you chose here will be your new defaults and will be used in the menubar pop-over app as well.")
                        Text("• **Download / Cancel** – start a job with one click and stop it at any time with the Cancel button.")
                        Text("• **Hide & show** – closing this window hides it (and the Dock icon). Click the menu‑bar icon to bring it back.")
                    }
                    .font(.callout)
                    .padding(.top, 2)
                } label: {
                    Label("Quick tour", systemImage: "info.circle")
                }
                .padding(.top, 12)

                // Destination
                HStack {
                    Label(destinationFolder.lastPathComponent, systemImage: "folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Change…", action: selectFolder)
                }

                // Type selector
                Picker("Download Type", selection: downloadType) {
                    ForEach(DownloadType.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                // Video options
                if downloadType.wrappedValue != .audio {
                    Grid(horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Text("Resolution")
                            Picker("", selection: $selectedResolution) {
                                ForEach(resolutionOptions, id: \.self) { Text("\($0)p") }
                            }
                            .pickerStyle(.menu)
                        }
                        GridRow {
                            Text("Container")
                            Picker("", selection: $selectedVideoFormat) {
                                ForEach(videoFormatOptions, id: \.self) { Text($0.uppercased()) }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Audio options
                if downloadType.wrappedValue != .video {
                    Grid(horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Text("Quality")
                            Picker("", selection: $selectedAudioQuality) {
                                ForEach(audioQualityOptions, id: \.self) { Text($0) }
                            }
                            .pickerStyle(.menu)
                        }
                        GridRow {
                            Text("Format")
                            Picker("", selection: $selectedAudioFormat) {
                                ForEach(audioFormatOptions, id: \.self) { Text($0.uppercased()) }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Download / cancel button
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

                // Spinner + status
                if isDownloading { ProgressView() }
                Text(downloadStatus).font(.subheadline)

                Spacer(minLength: 0)
            }
            .padding(32)
            .animation(.easeInOut, value: downloadType.wrappedValue)
        }
        .frame(width: 420, height: 540)
        .tint(.red)                     // accent colour for this window
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
        guard FileManager.default.fileExists(atPath: destinationFolder.path) else {
            downloadStatus = "Destination folder not found."
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

        let path = destinationFolder.path.escaped()
        let cmd  = "cd \(path) && /opt/homebrew/bin/yt-dlp \(formatOpt) \"\(videoURL.escaped())\""

        let proc = Process()
        proc.launchPath = "/bin/zsh"
        proc.arguments  = ["-c", cmd]
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
