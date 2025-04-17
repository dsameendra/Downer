//
//  ContentView.swift
//  Downer
//
//  Created by Dumindu Sameendra on 2025-04-17.
//

import SwiftUI
import AppKit   // for NSOpenPanel

struct ContentView: View {
    enum DownloadType: String, CaseIterable, Identifiable {
        case both  = "Video + Audio"
        case audio = "Audio Only"
        case video = "Video Only"
        var id: String { rawValue }
    }

    @State private var videoURL: String = ""
    @State private var downloadStatus: String = "Idle"

    // Destination folder (default to Downloads)
    @State private var destinationFolder: URL = {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }()

    // Download type
    @State private var downloadType: DownloadType = .both

    // Video options
    private let resolutionOptions = ["1080","720","480","360"]
    @State private var selectedResolution = "1080"

    private let videoFormatOptions = ["mp4","mkv", "mov", "webm"]
    @State private var selectedVideoFormat = "mp4"

    // 4) Audio options
    private let audioQualityOptions = ["320k","256k","192k","128k","64k"]
    @State private var selectedAudioQuality = "128k"

    private let audioFormatOptions = ["mp3","m4a","opus"]
    @State private var selectedAudioFormat = "mp3"

    var body: some View {
        VStack(spacing: 20) {
            Text("Downer")
                .font(.title)
                .padding(.top)

            // URL input
            TextField("Enter YouTube URL", text: $videoURL)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            // Destination selector
            HStack {
                Text("Save to:")
                Text(destinationFolder.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Change…", action: selectFolder)
            }
            .padding(.horizontal)

            // Download type
            Picker("Type", selection: $downloadType) {
                ForEach(DownloadType.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)

            // Video settings
            if downloadType != .audio {
                HStack {
                    Text("Resolution:")
                    Picker("", selection: $selectedResolution) {
                        ForEach(resolutionOptions, id: \.self) {
                            Text("\($0)p")
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    Text("Container:")
                    Picker("", selection: $selectedVideoFormat) {
                        ForEach(videoFormatOptions, id: \.self) {
                            Text($0)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                .padding(.horizontal)
            }

            // Audio settings
            if downloadType != .video {
                HStack {
                    Text("Quality:")
                    Picker("", selection: $selectedAudioQuality) {
                        ForEach(audioQualityOptions, id: \.self) {
                            Text($0)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())

                    Text("Format:")
                    Picker("", selection: $selectedAudioFormat) {
                        ForEach(audioFormatOptions, id: \.self) {
                            Text($0)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                .padding(.horizontal)
            }

            // Download button
            Button("Download") {
                startDownload()
            }
            .disabled(videoURL.isEmpty)
            .padding()

            // Status
            Text(downloadStatus)
                .foregroundColor(.gray)
                .padding()

            Spacer()
        }
        .frame(width: 500, height: 480)
        .padding()
    }

    /// Opens an NSOpenPanel to pick a folder
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                destinationFolder = url
            }
        }
    }

    private func startDownload() {
        downloadStatus = "Starting download…"

        // ensure folder exists
        guard FileManager.default.fileExists(atPath: destinationFolder.path) else {
            downloadStatus = "Destination folder not found."
            return
        }

        // build format flags
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

        // escape paths & URL
        let safeURL  = videoURL.escaped()
        let safePath = destinationFolder.path.escaped()
        let ytDlp    = "/opt/homebrew/bin/yt-dlp"

        // construct shell command
        let cmd = #"""
          cd \#(safePath) &&
          \#(ytDlp)\#(formatOpt) "\#(safeURL)"
        """#

        // launch process
        let proc = Process()
        proc.launchPath  = "/bin/zsh"
        proc.arguments  = ["-c", cmd]

        // ensure ffmpeg is on PATH
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:" + (env["PATH"] ?? "")
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = pipe

        // read live output
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let out = String(data: data, encoding: .utf8),
               !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DispatchQueue.main.async {
                    downloadStatus = out.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        // completion handler
        proc.terminationHandler = { p in
            DispatchQueue.main.async {
                downloadStatus = (p.terminationStatus == 0)
                    ? "Download completed. Check \(destinationFolder.lastPathComponent)."
                    : "Download failed (code \(p.terminationStatus))."
            }
        }

        do {
            try proc.run()
        } catch {
            downloadStatus = "Error launching yt-dlp: \(error.localizedDescription)"
        }
    }
}

extension String {
    func escaped() -> String {
        self
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: " ", with: "\\ ")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
