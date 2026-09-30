//
//  PlaylistTray.swift
//  Downer
//
//  The bottom tray that replaces the dock while a playlist downloads. Drag the
//  handle up to see every item, down to tuck it away; tap the header to toggle.
//

import AppKit
import SwiftUI

struct PlaylistTray: View {
    let playlist: PlaylistProgress
    let isDownloading: Bool
    let status: String
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onReveal: () -> Void
    let onDismiss: () -> Void
    /// 0 when peeking … 1 when fully open. The window behind dims with it.
    @Binding var expansion: CGFloat
    /// Opens the tray at launch; used for previews and tests.
    var startsOpen = false

    private static let peek: CGFloat = 162
    private static let list: CGFloat = 452
    private static let full: CGFloat = 604
    private static let detents: [CGFloat] = [peek, list, full]

    @State private var settled: CGFloat = PlaylistTray.peek
    @GestureState private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var height: CGFloat {
        min(Self.full, max(Self.peek, settled - drag))
    }

    /// 0…1 between the peeking and list heights; drives the cross-fade of content.
    private var reveal: CGFloat {
        min(1, max(0, (height - Self.peek) / (Self.list - Self.peek)))
    }

    var body: some View {
        VStack(spacing: 0) {
            handle
            header
            progressBar
            currentLine
                .opacity(1 - reveal)
                .frame(height: reveal > 0.98 ? 0 : nil)
            itemList
                .opacity(reveal)
            footer
                .opacity(reveal)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .frame(height: height, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .downerGlass(in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .onChange(of: height) { _, _ in
            expansion = min(1, max(0, (height - Self.peek) / (Self.list - Self.peek)))
        }
        .animation(Motion.standard(reduce: reduceMotion), value: settled)
        .onAppear { if startsOpen { settled = Self.list } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playlist downloads")
    }

    // MARK: Pieces
    private var handle: some View {
        Capsule()
            .fill(Color.primary.opacity(0.3))
            .frame(width: 38, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .onTapGesture(perform: toggle)
            .accessibilityLabel("Download list")
            .accessibilityHint("Drag or activate to show or hide every item")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggle() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(playlist.title.isEmpty ? "Playlist" : playlist.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            Button(action: isDownloading ? onCancel : onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(GlassCircleButtonStyle(size: 30))
            .help(isDownloading ? "Cancel playlist" : "Dismiss")
            .accessibilityLabel(isDownloading ? "Cancel playlist" : "Dismiss")
            ring
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onTapGesture(perform: toggle)
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 4)
            Circle()
                .trim(from: 0, to: isDownloading ? max(0.02, playlist.overall) : 1)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(ringLabel)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .contentTransition(.numericText())
        }
        .frame(width: 44, height: 44)
        .motion(value: playlist.overall)
        .accessibilityElement()
        .accessibilityLabel("Playlist progress")
        .accessibilityValue(ringLabel)
    }

    private var progressBar: some View {
        VStack(spacing: 7) {
            DownerProgressBar(value: isDownloading ? max(0.01, playlist.overall) : 1, tint: barColor)
            HStack {
                Text(leftLabel)
                Spacer()
                if isDownloading, let speed = playlist.speed { Text(speed) }
            }
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
            .motion(Motion.quick, value: playlist.current)
        }
        .padding(.horizontal, 4)
        .padding(.top, 10)
    }

    private var currentLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isDownloading ? Color.orange : (playlist.failed.isEmpty ? Color.green : Color.orange))
                .frame(width: 7, height: 7)
                .symbolEffect(.pulse, isActive: isDownloading)
            Text(currentTitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, 9)
        .motion(Motion.quick, value: currentTitle)
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(playlist.items) { item in
                        PlaylistRow(item: item, onRetry: onRetry)
                            .id(item.id)
                    }
                }
                .padding(.top, 6)
            }
            .scrollIndicators(.never)
            .defaultScrollAnchor(.top)
            .mask(
                LinearGradient(
                    stops: [.init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                    startPoint: .top, endPoint: .bottom)
            )
            .onChange(of: isDownloading) { _, running in
                // when the run ends, bring the first failure into view
                guard !running, let failed = playlist.failed.first else { return }
                withAnimation(Motion.standard(reduce: reduceMotion)) {
                    proxy.scrollTo(failed.id, anchor: .center)
                }
            }
            .onChange(of: playlist.current) { _, current in
                guard let current, reveal > 0.5 else { return }
                withAnimation(Motion.standard(reduce: reduceMotion)) {
                    proxy.scrollTo(current, anchor: .center)
                }
            }
        }
        .padding(.top, 8)
        .allowsHitTesting(reveal > 0.6)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if isDownloading {
                Button("Cancel Playlist", action: onCancel)
                    .buttonStyle(DownloadButtonStyle(isCancel: true, height: 46))
            } else {
                Button(action: onReveal) {
                    Label("Show in Finder", systemImage: "folder")
                }
                .buttonStyle(DownloadButtonStyle(height: 46))
                if !playlist.failed.isEmpty {
                    Button(action: onRetry) {
                        Label("Retry \(playlist.failed.count) failed", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(DownloadButtonStyle(isCancel: true, height: 46))
                }
            }
        }
        .padding(.top, 10)
        .allowsHitTesting(reveal > 0.6)
        .motion(value: isDownloading)
    }

    // MARK: Text
    private var subtitle: String {
        if isDownloading { return "Playlist · \(playlist.total) videos" }
        let failed = playlist.failed.count
        return failed == 0
            ? "Playlist · \(playlist.doneCount) of \(playlist.total) downloaded"
            : "Playlist · \(playlist.doneCount) of \(playlist.total) downloaded · \(failed) failed"
    }

    private var leftLabel: String {
        if isDownloading {
            return playlist.current.map { "Item \($0) of \(playlist.total)" } ?? "Preparing…"
        }
        return playlist.failed.isEmpty ? "All \(playlist.total) downloaded" : "\(playlist.failed.count) failed"
    }

    private var currentTitle: String {
        if let current = playlist.current, isDownloading {
            return playlist.items[current - 1].title ?? "Item \(current)"
        }
        return status
    }

    private var ringLabel: String {
        isDownloading
            ? "\(Int((playlist.overall * 100).rounded()))%"
            : "\(playlist.doneCount)/\(playlist.total)"
    }

    private var ringColor: Color {
        isDownloading ? Brand.red : (playlist.failed.isEmpty ? .green : .orange)
    }

    private var barColor: Color {
        isDownloading ? Brand.red : (playlist.failed.isEmpty ? .green : .orange)
    }

    // MARK: Interaction
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($drag) { value, state, _ in state = value.translation.height }
            .onEnded { value in
                let predicted = settled - value.predictedEndTranslation.height
                let target = Self.detents.min { abs($0 - predicted) < abs($1 - predicted) } ?? Self.peek
                settled = min(Self.full, max(Self.peek, target))
                expansion = min(1, max(0, (settled - Self.peek) / (Self.list - Self.peek)))
            }
    }

    private func toggle() {
        settled = settled > Self.peek + 1 ? Self.peek : Self.list
        expansion = settled > Self.peek + 1 ? 1 : 0
    }
}

// MARK: - Row
private struct PlaylistRow: View {
    let item: PlaylistItem
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title ?? "Item \(item.id)")
                    .font(.system(size: 14, weight: item.state == .running ? .semibold : .medium))
                    .foregroundStyle(item.state == .queued ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 8)
            if item.state == .failed {
                Button("Retry", action: onRetry)
                    .buttonStyle(PillButtonStyle())
            } else if item.state == .running {
                Text("\(Int((item.fraction * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 52)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
        .motion(Motion.quick, value: item.state)
        .motion(value: item.fraction)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        switch item.state {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: item.state)
        case .running:
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.03, item.fraction))
                    .stroke(Brand.red, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 24, height: 24)
        case .queued:
            Circle()
                .strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.6, dash: [3, 3]))
                .frame(width: 20, height: 20)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.orange)
        }
    }

    private var detail: String {
        switch item.state {
        case .done: return "Downloaded"
        case .running: return "Downloading"
        case .queued: return "Waiting"
        case .failed: return item.detail ?? "Failed"
        }
    }
}
