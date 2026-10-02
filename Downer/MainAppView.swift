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
    @State private var infoExpanded = false
    @FocusState private var urlFocused: Bool
    @State private var trayExpansion: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var deps = DependencyManager.shared
    @ObservedObject private var dl = DownloadManager.shared

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

    // MARK: - Body
    var body: some View {
        ZStack {
            AmbientBackground()

            ScrollView {
                VStack(spacing: 14) {
                    setupBanner
                    urlField.appear(0)
                    typeSelector.appear(1)
                    optionGroups.appear(2)
                    saveLocation.appear(3)
                    informationSection.appear(4)
                }
                .padding(.horizontal, 20)
                .padding(.top, -6)
                .padding(.bottom, 150)
                .motion(value: deps.missing.isEmpty)
            }
            .scrollIndicators(.never)
            .scaleEffect(1 - 0.015 * trayExpansion, anchor: .top)
            .blur(radius: 2 * trayExpansion)

            Color.black.opacity(0.32 * trayExpansion)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                TitleBarRow(title: "Downer") {
                    SettingsLink {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(GlassCircleButtonStyle())
                    .help("Settings")
                }
                Spacer()
            }

            VStack {
                Spacer()
                // one panel, one glass shape: it grows from the dock into the tray and back
                QueueTray(
                    jobs: dl.jobs,
                    status: dl.status,
                    onCancelAll: { dl.cancelAll() },
                    onRemove: { dl.remove($0) },
                    onRetry: { dl.retry($0) },
                    onRetryAll: { dl.retryAllFailed() },
                    onReveal: { dl.revealFiles() },
                    onRevealJob: { dl.reveal(job: $0) },
                    onMove: { dl.move($0, toIndex: $1) },
                    onDismiss: { withAnimation(Motion.standard(reduce: reduceMotion)) { dl.clearFinished() } },
                    expansion: $trayExpansion,
                    startsOpen: DownloadManager.previewTrayOpen,
                    isTray: dl.needsTray,
                    dock: AnyView(dockContent)
                )
            }
            .padding(14)
            .onChange(of: dl.needsTray) { _, needs in
                if !needs { trayExpansion = 0 }
            }
        }
        // 460 × 640 below the title bar; the window adds the title bar's own height
        .frame(width: 460, height: 640)
        .linkDrop { dl.add($0) }
        .tint(Brand.red)
        .onChange(of: downloadType.wrappedValue) { oldType, newType in
            if newType != .audio {
                selectedAudioFormat = "source"
            }
        }
    }

    // MARK: - Sections
    @ViewBuilder
    private var setupBanner: some View {
        if !deps.missing.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Setup needed")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(deps.missing.map(\.title).joined(separator: ", ")) not found")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                SettingsLink { Text("Set up") }
                    .buttonStyle(PillButtonStyle())
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .frame(height: 52)
            .downerSurface()
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var urlField: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(urlFocused ? Brand.red : Color.secondary)

            TextField("Enter video/playlist URL", text: $videoURL)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($urlFocused)
                .onSubmit(submit)

            if !videoURL.isEmpty {
                Button {
                    videoURL = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear URL")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .frame(height: 54)
        .downerGlass(in: Capsule())
        .overlay(Capsule().strokeBorder(Brand.red.opacity(urlFocused ? 0.55 : 0), lineWidth: 1.5))
        .motion(Motion.quick, value: urlFocused)
        .motion(Motion.quick, value: videoURL.isEmpty)
    }

    private var typeSelector: some View {
        GlassSegmentedControl(
            options: DownloadType.allCases.map { .init(value: $0, title: $0.rawValue) },
            selection: downloadType,
            label: "Download type")
    }

    @ViewBuilder
    private var optionGroups: some View {
        VStack(spacing: 14) {
            if downloadType.wrappedValue != .audio {
                OptionGroup(title: "Video") {
                    OptionRow(
                        title: "Resolution",
                        options: resolutionOptions.map { "\($0)p" },
                        selection: Binding(
                            get: { "\(selectedResolution)p" },
                            set: {
                                selectedResolution = $0.replacingOccurrences(of: "p", with: "")
                            }
                        )
                    )
                    OptionRow(
                        title: "Container",
                        options: videoFormatOptions.map { $0.uppercased() },
                        selection: Binding(
                            get: { selectedVideoFormat.uppercased() },
                            set: { selectedVideoFormat = $0.lowercased() }
                        ),
                        showsDivider: false
                    )
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            if downloadType.wrappedValue != .video {
                OptionGroup(title: "Audio") {
                    OptionRow(
                        title: "Quality",
                        options: audioQualityOptions.map { $0.label },
                        selection: Binding(
                            get: {
                                audioQualityOptions.first(where: { $0.value == selectedAudioQuality })?.label ?? ""
                            },
                            set: { newLabel in
                                if let option = audioQualityOptions.first(where: { $0.label == newLabel }) {
                                    selectedAudioQuality = option.value
                                }
                            }
                        ),
                        showsDivider: downloadType.wrappedValue == .audio
                    )
                    if downloadType.wrappedValue == .audio {
                        OptionRow(
                            title: "Format",
                            options: audioFormatOptions.map { $0.label },
                            selection: Binding(
                                get: {
                                    audioFormatOptions.first(where: { $0.value == selectedAudioFormat })?.label ?? ""
                                },
                                set: { newLabel in
                                    if let option = audioFormatOptions.first(where: { $0.label == newLabel }) {
                                        selectedAudioFormat = option.value
                                    }
                                }
                            ),
                            showsDivider: false
                        )
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .motion(value: downloadType.wrappedValue)
    }

    private var saveLocation: some View {
        OptionGroup(title: "Save to") {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                Text(destinationFolder.relativePath)
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button("Change", action: selectFolder)
                    .buttonStyle(PillButtonStyle())
            }
            .padding(.leading, 14)
            .padding(.trailing, 9)
            .frame(height: 50)
        }
    }

    private var informationSection: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(Motion.standard(reduce: reduceMotion)) { infoExpanded.toggle() }
            } label: {
                HStack {
                    Text("Information")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(infoExpanded ? 90 : 0))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if infoExpanded {
                VStack(alignment: .leading, spacing: 12) {
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
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .downerSurface()
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var addsToQueue: Bool { !videoURL.isEmpty && dl.isActive }
    private var cancels: Bool { videoURL.isEmpty && dl.isActive }

    /// Adds what is in the field (one link or several) to the queue and clears it.
    private func submit() {
        guard !videoURL.isEmpty else { return }
        if dl.add(videoURL) > 0 {
            withAnimation(Motion.standard(reduce: reduceMotion)) { videoURL = "" }
        }
    }

    /// The single-download controls. The panel around them (glass, height) belongs to `QueueTray`.
    private var dockContent: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(Motion.standard(reduce: reduceMotion)) {
                    if cancels { dl.cancelAll() } else { submit() }
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: cancels ? "xmark" : (addsToQueue ? "plus" : "arrow.down"))
                        .font(.system(size: 15, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(cancels ? "Cancel Download" : (addsToQueue ? "Add to Queue" : "Download"))
                        .contentTransition(.opacity)
                }
                .motion(Motion.quick, value: cancels)
                .motion(Motion.quick, value: addsToQueue)
            }
            .buttonStyle(DownloadButtonStyle(isCancel: cancels))
            .keyboardShortcut(cancels ? nil : .defaultAction)
            .disabled(videoURL.isEmpty && !dl.isActive)

            if dl.isActive {
                DownerProgressBar(value: dl.runningJob == nil ? nil : dl.progress)
                    .padding(.horizontal, 14)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }

            DownloadStatusLine(
                status: dl.status,
                isDownloading: dl.isActive,
                completions: dl.completions
            )
            .frame(minHeight: 18)

            if !dl.lastFiles.isEmpty && !dl.isActive {
                Button {
                    dl.revealFiles()
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .buttonStyle(PillButtonStyle())
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .padding(12)
        .motion(value: dl.isActive)
        .motion(value: dl.lastFiles.isEmpty)
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
}

// MARK: - Supporting Views
struct OptionGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
            VStack(spacing: 0) { content() }
                .downerSurface()
        }
    }
}

struct OptionRow: View {
    let title: String
    let options: [String]
    @Binding var selection: String
    var showsDivider = true

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
            Spacer()
            Menu {
                Picker(title, selection: $selection) {
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack(spacing: 6) {
                    Text(selection)
                        .font(.system(size: 13, weight: .medium))
                        .contentTransition(.opacity)
                        .motion(Motion.quick, value: selection)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 12)
                .padding(.trailing, 9)
                .frame(height: 28)
                .background(Color.primary.opacity(0.10), in: Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.leading, 14)
        .padding(.trailing, 9)
        .frame(height: 46)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Divider().opacity(0.6).padding(.horizontal, 14)
            }
        }
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
                .foregroundColor(Brand.red.opacity(0.9))
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
