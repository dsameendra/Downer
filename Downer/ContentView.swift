//
//  ContentView.swift
//  Downer
//
//  Created by Dumindu Sameendra on 2025-04-17.
//

import SwiftUI
import AppKit // for NSOpenPanel

struct ContentView: View {
    enum DownloadType: String, CaseIterable, Identifiable {
        case both  = "Video + Audio"
        case audio = "Audio Only"
        case video = "Video Only"
        var id: String { rawValue }
    }

    @State private var videoURL: String = ""
    @State private var downloadStatus: String = "Idle"
    @State private var isDownloading = false

    // Destination folder
    @State private var destinationFolder: URL = {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }()

    // Download type
    @State private var downloadType: DownloadType = .both

    // Video options
    private let resolutionOptions = ["4320", "2160", "1080","720","480","360","240"]
    @State private var selectedResolution = "1080"
    private let videoFormatOptions = ["mp4","mkv","webm"]
    @State private var selectedVideoFormat = "mp4"

    // Audio options
    private let audioQualityOptions = ["320k","256k","192k","128k","64k"]
    @State private var selectedAudioQuality = "320k"
    private let audioFormatOptions = ["mp3","m4a","opus"]
    @State private var selectedAudioFormat = "mp3"

    var body: some View {
        ZStack {
            VStack(spacing: 24) {

                // URL input
                TextField("Enter YouTube URL", text: $videoURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    .disableAutocorrection(true)

                // Destination folder
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.white)
                    Text(destinationFolder.lastPathComponent)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(action: selectFolder) {
                        Text("Change…")
                            .font(.callout)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
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
                .accentColor(.white)
                .animation(.easeInOut, value: downloadType)

                // Video settings
                if downloadType != .audio {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Resolution:")
                                .foregroundColor(.white)
                            Picker("", selection: $selectedResolution) {
                                ForEach(resolutionOptions, id: \.self) {
                                    Text("\($0)p")
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 80)
                        }
                        .padding(.horizontal)

                        HStack {
                            Text("Container:")
                                .foregroundColor(.white)
                            Picker("", selection: $selectedVideoFormat) {
                                ForEach(videoFormatOptions, id: \.self) {
                                    Text($0.uppercased())
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 100)
                        }
                        .padding(.horizontal)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Audio settings
                if downloadType != .video {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Quality:")
                                .foregroundColor(.white)
                            Picker("", selection: $selectedAudioQuality) {
                                ForEach(audioQualityOptions, id: \.self) {
                                    Text($0)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 80)
                        }
                        .padding(.horizontal)

                        HStack {
                            Text("Format:")
                                .foregroundColor(.white)
                            Picker("", selection: $selectedAudioFormat) {
                                ForEach(audioFormatOptions, id: \.self) {
                                    Text($0.uppercased())
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 100)
                        }
                        .padding(.horizontal)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Download button & progress
                ZStack {
                    Button(action: startDownload) {
                        Text(isDownloading ? "Downloading..." : "Download")
                            .font(.headline)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                            .scaleEffect(isDownloading ? 0.95 : 1.0)
                    }
                    .disabled(videoURL.isEmpty || isDownloading)
                    .padding(.horizontal)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDownloading)

                    if isDownloading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                }

                // Status text
                Text(downloadStatus)
                    .foregroundColor(.white.opacity(0.9))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .transition(.opacity)
                    .animation(.easeIn, value: downloadStatus)

                Spacer()
            }
            .padding(.top, 30)
        }
    }

    // MARK: - Folder Picker
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

    // MARK: - Start Download
    private func startDownload() {
        withAnimation { isDownloading = true }
        downloadStatus = "Starting download…"

        // ensure folder exists
        guard FileManager.default.fileExists(atPath: destinationFolder.path) else {
            downloadStatus = "Destination folder not found."
            withAnimation { isDownloading = false }
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

        let safeURL  = videoURL.escaped()
        let safePath = destinationFolder.path.escaped()
        let ytDlp    = "/opt/homebrew/bin/yt-dlp"
        let cmd = #"""
          cd \#(safePath) &&
          \#(ytDlp)\#(formatOpt) "\#(safeURL)"
        """#

        let proc = Process()
        proc.launchPath = "/bin/zsh"
        proc.arguments  = ["-c", cmd]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:" + (env["PATH"] ?? "")
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let out = String(data: data, encoding: .utf8),
               !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DispatchQueue.main.async {
                    withAnimation { downloadStatus = out.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
            }
        }

        proc.terminationHandler = { p in
            DispatchQueue.main.async {
                withAnimation {
                    isDownloading = false
                    downloadStatus = (p.terminationStatus == 0)
                        ? "Download completed. Check \(destinationFolder.lastPathComponent)."
                        : "Download failed (code \(p.terminationStatus))."
                }
            }
        }

        do {
            try proc.run()
        } catch {
            downloadStatus = "Error launching yt-dlp: \(error.localizedDescription)"
            withAnimation { isDownloading = false }
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
