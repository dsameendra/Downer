//
//  ContentView.swift
//  Downer
//
//  Created by Dumindu Sameendra on 2025-04-17.
//

import SwiftUI

struct ContentView: View {
    enum DownloadType: String, CaseIterable, Identifiable {
        case audio = "Audio Only"
        case video = "Video Only"
        case both  = "Video + Audio"
        var id: String { rawValue }
    }

    @State private var videoURL: String = ""
    @State private var downloadStatus: String = "Idle"

    // User selections
    @State private var downloadType: DownloadType = .both
    private let resolutionOptions = ["1080","720","480","360","240"]
    @State private var selectedResolution = "720"
    private let audioQualityOptions = ["320k","256k","192k","128k","64k"]
    @State private var selectedAudioQuality = "128k"

    var body: some View {
        VStack(spacing: 20) {
            Text("Downer")
                .font(.title)
                .padding(.top)

            TextField("Enter YouTube URL", text: $videoURL)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            // 1) Download type picker
            Picker("Type", selection: $downloadType) {
                ForEach(DownloadType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)

            // 2) Resolution (only when video or both)
            if downloadType != .audio {
                HStack {
                    Text("Resolution:")
                    Picker("", selection: $selectedResolution) {
                        ForEach(resolutionOptions, id: \.self) { r in
                            Text("\(r)p").tag(r)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                .padding(.horizontal)
            }

            // 3) Audio quality (only when audio or both)
            if downloadType != .video {
                HStack {
                    Text("Audio Quality:")
                    Picker("", selection: $selectedAudioQuality) {
                        ForEach(audioQualityOptions, id: \.self) { q in
                            Text(q).tag(q)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                .padding(.horizontal)
            }

            Button("Download") {
                downloadYouTube(
                    url: videoURL,
                    type: downloadType,
                    resolution: selectedResolution,
                    audioQuality: selectedAudioQuality
                )
            }
            .disabled(videoURL.isEmpty)
            .padding()

            Text(downloadStatus)
                .foregroundColor(.gray)
                .padding()

            Spacer()
        }
        .frame(width: 400, height: 400)
        .padding()
    }

    func downloadYouTube(
        url: String,
        type: DownloadType,
        resolution: String,
        audioQuality: String
    ) {
        downloadStatus = "Starting download..."
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
        guard FileManager.default.fileExists(atPath: desktop.path) else {
            downloadStatus = "Desktop folder not found."
            return
        }

        // Build yt-dlp format string
        let formatOpt: String
        switch type {
        case .audio:
            // bestaudio, extract to mp3, set quality
            formatOpt =
            #" -f bestaudio --extract-audio --audio-format mp3 --audio-quality "# + audioQuality
        case .video:
            // bestvideo up to chosen height, no audio
            formatOpt =
            #" -f "bestvideo[height<=\#(resolution)]" --merge-output-format mp4 --no-audio "#
        case .both:
            // separate bestvideo + bestaudio, then merge to mp4
            formatOpt =
            #" -f "bestvideo[height<=\#(resolution)]+bestaudio" --merge-output-format mp4 "#
        }

        let safeURL = url.escaped()
        let safePath = desktop.path.escaped()
        let ytDlp = "/opt/homebrew/bin/yt-dlp"
        let ffmpegLocation = "/opt/homebrew/bin/ffmpeg"
        let ffmpegOpt = " --ffmpeg-location \(ffmpegLocation)"

        let cmd = #"""
          cd \#(safePath) &&
          \#(ytDlp)\#(formatOpt)\#(ffmpegOpt) "\#(safeURL)"
        """#

        print("Running command:", cmd)
        let proc = Process()
        proc.launchPath = "/bin/zsh"
        proc.arguments = ["-c", cmd]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let out = String(data: data, encoding: .utf8), !out.isEmpty {
                DispatchQueue.main.async {
                    self.downloadStatus = out.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                print("> ", out)
            }
        }

        proc.terminationHandler = { p in
            DispatchQueue.main.async {
                if p.terminationStatus == 0 {
                    self.downloadStatus = "Download completed. Check Desktop."
                } else {
                    self.downloadStatus = "Download failed (code \(p.terminationStatus))."
                }
            }
            print("Process exited:", p.terminationStatus)
        }

        do {
            try proc.run()
            print("Process launched.")
        } catch {
            downloadStatus = "Failed to start yt-dlp: \(error.localizedDescription)"
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
