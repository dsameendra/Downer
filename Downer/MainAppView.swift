//
//  MainAppView.swift
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

    // configurable download settings
    @AppStorage("downloadType") private var downloadTypeRaw = DownloadType.both
        .rawValue
    @AppStorage("selectedResolution") private var selectedResolution = "1080"
    @AppStorage("selectedVideoFormat") private var selectedVideoFormat = "mp4"
    @AppStorage("selectedAudioQuality") private var selectedAudioQuality =
        "source"
    @AppStorage("selectedAudioFormat") private var selectedAudioFormat = "opus"
    @AppStorage("destinationFolder") private var destinationFolderPath =
        FileManager.default
        .urls(for: .downloadsDirectory, in: .userDomainMask)
        .first!
        .path

    @State private var videoURL = ""
    @State private var downloadStatus = "Idle"
    @State private var isDownloading = false
    @State private var currentProcess: Process?
    @State private var infoExpanded = false

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

    private let audioQualityOptions: [(label: String, value: String)] = [
        ("Best available", "source"),
        ("Up to 128 kbps", "128k"),
        ("Up to 70 kbps", "70k"),
        ("Up to 50 kbps", "50k"),
    ]

    private let audioFormatOptions: [(label: String, value: String)] = [
        ("Source (no transcode)", "source"),
        ("MP3", "mp3"),
        ("AAC (M4A)", "m4a"),
        ("Opus", "opus"),
    ]

    @Environment(\.colorScheme) var colorScheme

    private var glassBackground: some View {
        ZStack {
            if colorScheme == .dark {
                Color.black.opacity(0.15)
            } else {
                Color.white.opacity(0.15)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 3)
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
                    colorScheme == .dark ? Color.black : Color(white: 0.95),
                    colorScheme == .dark ? Color(white: 0.15) : Color.white,
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Color.clear.frame(height: 1)

                ScrollView {
                    VStack(alignment: .center, spacing: 10) {
                        // URL Field
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Media URL")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            ZStack(alignment: .leading) {
                                RoundedRectangle(
                                    cornerRadius: 10,
                                    style: .continuous
                                )
                                .fill(.ultraThinMaterial)
                                .frame(height: 38)
                                .overlay(
                                    RoundedRectangle(
                                        cornerRadius: 10,
                                        style: .continuous
                                    )
                                    .stroke(
                                        Color.white.opacity(0.2),
                                        lineWidth: 1
                                    )
                                )

                                HStack {
                                    Image(systemName: "link")
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 10)

                                    TextField(
                                        "Enter video/playlist URL",
                                        text: $videoURL
                                    )
                                    .textFieldStyle(.plain)
                                    .padding(.vertical, 10)

                                    if !videoURL.isEmpty {
                                        Button(action: { videoURL = "" }) {
                                            Image(
                                                systemName: "xmark.circle.fill"
                                            )
                                            .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.trailing, 10)
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)

                        // Destination folder
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Save Location")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                ZStack {
                                    RoundedRectangle(
                                        cornerRadius: 10,
                                        style: .continuous
                                    )
                                    .fill(.ultraThinMaterial)
                                    .frame(height: 38)
                                    .overlay(
                                        RoundedRectangle(
                                            cornerRadius: 10,
                                            style: .continuous
                                        )
                                        .stroke(
                                            Color.white.opacity(0.2),
                                            lineWidth: 1
                                        )
                                    )

                                    HStack {
                                        Image(systemName: "folder")
                                            .foregroundColor(.secondary)
                                            .padding(.leading, 10)

                                        Text(
                                            destinationFolder.relativePath
                                        )
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .padding(.vertical, 10)

                                        Spacer()
                                    }
                                }

                                Button(action: selectFolder) {
                                    Text("Change")
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 9)
                                        .background(
                                            RoundedRectangle(
                                                cornerRadius: 10,
                                                style: .continuous
                                            )
                                            .fill(brandGradient)
                                        )
                                }
                                .buttonStyle(.plain)
                                .frame(width: 75)
                            }
                        }

                        // Download Type Selector
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Download Type")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            ZStack {
                                RoundedRectangle(
                                    cornerRadius: 10,
                                    style: .continuous
                                )
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(
                                        cornerRadius: 10,
                                        style: .continuous
                                    )
                                    .stroke(
                                        Color.white.opacity(0.2),
                                        lineWidth: 1
                                    )
                                )

                                HStack(spacing: 2) {
                                    ForEach(DownloadType.allCases) { type in
                                        Button(action: {
                                            withAnimation(
                                                .spring(response: 0.3)
                                            ) {
                                                downloadType.wrappedValue = type
                                            }
                                        }) {
                                            Text(type.rawValue)
                                                .fontWeight(.medium)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 8)
                                                .background(
                                                    downloadType.wrappedValue
                                                        == type
                                                        ? RoundedRectangle(
                                                            cornerRadius: 8,
                                                            style: .continuous
                                                        )
                                                        .fill(
                                                            LinearGradient(
                                                                gradient:
                                                                    Gradient(
                                                                        colors: [
                                                                            Color
                                                                                .red
                                                                                .opacity(
                                                                                    0.8
                                                                                ),
                                                                            Color
                                                                                .red
                                                                                .opacity(
                                                                                    0.6
                                                                                ),
                                                                        ]),
                                                                startPoint:
                                                                    .topLeading,
                                                                endPoint:
                                                                    .bottomTrailing
                                                            )
                                                        )
                                                        .shadow(
                                                            color: Color.red
                                                                .opacity(0.3),
                                                            radius: 4,
                                                            x: 0,
                                                            y: 2
                                                        )
                                                        : nil
                                                )
                                                .foregroundColor(
                                                    downloadType.wrappedValue
                                                        == type
                                                        ? .white : .primary
                                                )
                                                .contentShape(
                                                    RoundedRectangle(
                                                        cornerRadius: 10,
                                                        style: .continuous
                                                    )
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(3)
                                .animation(
                                    .spring(response: 0.3),
                                    value: downloadType.wrappedValue
                                )
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            // Video options
                            if downloadType.wrappedValue != .audio {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Video Options")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)

                                    // Resolution picker (fixed)
                                    GlassPickerView(
                                        title: "Resolution",
                                        options: resolutionOptions.map {
                                            "\($0)p"
                                        },
                                        selection: Binding(
                                            get: { "\(selectedResolution)p" },
                                            set: {
                                                selectedResolution =
                                                    $0.replacingOccurrences(
                                                        of: "p",
                                                        with: ""
                                                    )
                                            }
                                        )
                                    )

                                    // Format picker (fixed)
                                    GlassPickerView(
                                        title: "Container",
                                        options: videoFormatOptions.map {
                                            $0.uppercased()
                                        },
                                        selection: Binding(
                                            get: {
                                                selectedVideoFormat.uppercased()
                                            },
                                            set: {
                                                selectedVideoFormat =
                                                    $0.lowercased()
                                            }
                                        )
                                    )
                                }
                                .padding(16)
                                .background(glassBackground)
                                .transition(
                                    .asymmetric(
                                        insertion: .scale(scale: 0.95).combined(
                                            with: .opacity
                                        ),
                                        removal: .scale(scale: 0.95).combined(
                                            with: .opacity
                                        )
                                    )
                                )
                            }

                            // Audio options
                            if downloadType.wrappedValue != .video {
                                VStack(alignment: .leading, spacing: 16) {
                                    Text("Audio Options")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)

                                    // Audio quality picker
                                    GlassPickerView(
                                        title: "Quality",
                                        options: audioQualityOptions.map {
                                            $0.label
                                        },
                                        selection: Binding(
                                            get: {
                                                audioQualityOptions.first(
                                                    where: {
                                                        $0.value
                                                            == selectedAudioQuality
                                                    })?.label ?? ""
                                            },
                                            set: { newLabel in
                                                if let option =
                                                    audioQualityOptions.first(
                                                        where: {
                                                            $0.label == newLabel
                                                        })
                                                {
                                                    selectedAudioQuality =
                                                        option.value
                                                }
                                            }
                                        )
                                    )

                                    // Format picker (Audio only mode)
                                    if downloadType.wrappedValue == .audio {
                                        GlassPickerView(
                                            title: "Format",
                                            options: audioFormatOptions.map {
                                                $0.label
                                            },
                                            selection: Binding(
                                                get: {
                                                    audioFormatOptions.first(
                                                        where: {
                                                            $0.value
                                                                == selectedAudioFormat
                                                        })?.label ?? ""
                                                },
                                                set: { newLabel in
                                                    if let option =
                                                        audioFormatOptions.first(
                                                            where: {
                                                                $0.label
                                                                    == newLabel
                                                            })
                                                    {
                                                        selectedAudioFormat =
                                                            option.value
                                                    }
                                                }
                                            )
                                        )
                                    }
                                }
                                .padding(16)
                                .background(glassBackground)
                                .transition(
                                    .asymmetric(
                                        insertion: .scale(scale: 0.95).combined(
                                            with: .opacity
                                        ),
                                        removal: .scale(scale: 0.95).combined(
                                            with: .opacity
                                        )
                                    )
                                )
                            }
                        }
                        .animation(
                            .spring(response: 0.3, dampingFraction: 0.7),
                            value: downloadType.wrappedValue
                        )

                        // Information disclosure (condensed)
                        DisclosureGroup(isExpanded: $infoExpanded) {
                            VStack(alignment: .leading, spacing: 8) {
                                InfoRow(
                                    icon: "arrow.triangle.2.circlepath",
                                    title: "Persistent defaults",
                                    description:
                                        "Every choice here becomes your new default, and carries over to the menu‑bar pop‑over."
                                )

                                InfoRow(
                                    icon: "video.fill",
                                    title: "Video formats and quality",
                                    description:
                                        "In Video modes, the highest-quality video track up to your selected resolution is fetched and packaged in your chosen container."
                                )

                                InfoRow(
                                    icon: "music.note",
                                    title: "Audio format and quality",
                                    description:
                                        "'Up to' will select the highest-quality audio stream whose bitrate is at or below X kbps."
                                )

                                InfoRow(
                                    icon: "arrow.triangle.swap",
                                    title: "Transcoding",
                                    description:
                                        "Only runs when you choose a different format: picking 'Source' uses the source directly."
                                )

                                InfoRow(
                                    icon: "eye.slash",
                                    title: "Hide & show",
                                    description:
                                        "Closing the window hides it (and the Dock icon); click the menu‑bar icon to bring it back."
                                )
                            }
                            .padding(.top, 6)
                        } label: {
                            HStack {
                                Text("Information")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut) {
                                    infoExpanded.toggle()
                                }
                            }
                        }
                        .padding(14)
                        .background(glassBackground)
                        
                       
                    }
                    //                    .padding(18)
                    .padding(.horizontal, 18)  // no top padding
                    .padding(.bottom, 18)  // Extra bottom padding to ensure scrolling works properly
                }
                
                // Download button
                VStack(spacing: 6) {
                    Button {
                        if isDownloading {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                stopDownload()
                            }
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                startDownload()
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isDownloading {
                                Image(systemName: "xmark.circle.fill")
                                    .font(
                                        .system(
                                            size: 15,
                                            weight: .medium
                                        )
                                    )
                                Text("Cancel Download")
                                    .font(
                                        .system(
                                            size: 15,
                                            weight: .semibold
                                        )
                                    )
                            } else {
                                Image(
                                    systemName: "arrow.down.circle.fill"
                                )
                                .font(
                                    .system(size: 15, weight: .medium)
                                )
                                Text("Download")
                                    .font(
                                        .system(
                                            size: 15,
                                            weight: .semibold
                                        )
                                    )
                            }
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(
                            ZStack {
                                if isDownloading {
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.gray.opacity(0.8),
                                            Color.gray.opacity(0.6),
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                } else {
                                    brandGradient
                                }
                            }
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 12,
                                    style: .continuous
                                )
                            )
                        )
                        .foregroundColor(.white)
                        .shadow(
                            color: isDownloading
                                ? Color.gray.opacity(0.3)
                                : Color.red.opacity(0.4),
                            radius: 6,
                            x: 0,
                            y: 3
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(videoURL.isEmpty && !isDownloading)
                    .opacity(
                        videoURL.isEmpty && !isDownloading ? 0.6 : 1.0
                    )

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
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                    }
                    .frame(height: 60)
                    .animation(
                        .easeInOut(duration: 0.2),
                        value: isDownloading
                    )
                }
                .padding(.top, 8)
                .padding(.horizontal, 18)
            }
            .scrollIndicators(.never)
            .frame(width: 460, height: 700)
        }
        .tint(.red)
        .onChange(of: downloadType.wrappedValue) { oldType, newType in
            if newType != .audio {
                selectedAudioFormat = "source"
            }
        }
    }

    // MARK: - Helper Methods
    private func numericAbr(_ quality: String) -> Int? {
        Int(quality.replacingOccurrences(of: "k", with: ""))
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
            downloadStatus = "yt‑dlp not found.\nCheck Settings → Tool Paths."
            isDownloading = false
            return
        }
        guard FileManager.default.isExecutableFile(atPath: ffmpegPath),
            FileManager.default.isExecutableFile(atPath: ffprobePath)
        else {
            downloadStatus =
                "ffmpeg / ffprobe not found.\nCheck Settings → Tool Paths."
            isDownloading = false
            return
        }

        let audioFilter: String = {
            if selectedAudioQuality == "source" {  // best available
                return "bestaudio"
            }
            if let abr = numericAbr(selectedAudioQuality) {  // cap at chosen ABR
                return "bestaudio[abr<=\(abr)][vcodec=none]"
            }
            return "bestaudio"
        }()

        let formatOpt: String
        switch downloadType.wrappedValue {

        case .audio:
            var fmt = "-f \"\(audioFilter)\""
            if selectedAudioFormat != "source" {  // transcode only if asked
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
                -f "bestvideo[height<=\(selectedResolution)]+\(audioFilter)" \
                --merge-output-format \(selectedVideoFormat)
                """
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

        // Revert to idle after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if !self.isDownloading {
                self.downloadStatus = "Idle"
            }
        }
    }
}

// MARK: - Supporting Views
struct GlassPickerView: View {
    let title: String
    let options: [String]
    @Binding var selection: String

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .foregroundColor(.primary)
                .font(.system(size: 14))

            ZStack(alignment: .top) {
                if isExpanded {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(
                                .spring(response: 0.25, dampingFraction: 0.7)
                            ) {
                                isExpanded = false
                            }
                        }
                }

                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7))
                    {
                        isExpanded.toggle()
                    }
                }) {
                    HStack {
                        Text(selection)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(
                                    cornerRadius: 10,
                                    style: .continuous
                                )
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(spacing: 0) {
                        ForEach(options, id: \.self) { option in
                            Button {
                                withAnimation(
                                    .spring(
                                        response: 0.25,
                                        dampingFraction: 0.7
                                    )
                                ) {
                                    selection = option
                                    isExpanded = false
                                }
                            } label: {
                                ZStack(alignment: .leading) {
                                    if selection == option {
                                        RoundedRectangle(
                                            cornerRadius: 10,
                                            style: .continuous
                                        )
                                        .fill(Color.primary.opacity(0.1))
                                        .padding(-1)
                                    }

                                    HStack {
                                        Text(option)
                                            .font(.system(size: 14))
                                            .foregroundColor(
                                                selection == option
                                                    ? .red : .primary
                                            )
                                            .frame(
                                                maxWidth: .infinity,
                                                alignment: .leading
                                            )

                                        if selection == option {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12))
                                                .foregroundColor(.red)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                }
                                .contentShape(
                                    RoundedRectangle(
                                        cornerRadius: 10,
                                        style: .continuous
                                    )
                                )
                            }
                            .buttonStyle(.plain)

                            if option != options.last {
                                Divider().padding(.horizontal, 8)
                                    .foregroundStyle(
                                        Color.primary.opacity(0.15)
                                    )
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(
                                    cornerRadius: 10,
                                    style: .continuous
                                )
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .shadow(
                                color: Color.black.opacity(0.15),
                                radius: 8,
                                x: 0,
                                y: 4
                            )
                    )
                    .zIndex(1)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
            .compositingGroup()
            .zIndex(isExpanded ? 2 : 0)
        }
        .animation(.easeOut(duration: 0.2), value: isExpanded)
    }
}

struct InfoRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.red.opacity(0.8))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))

                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
