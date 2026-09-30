//
//  QueueTray.swift
//  Downer
//
//  The bottom tray that replaces the dock when more than one video is queued or
//  a playlist is downloading. Drag the handle up to see every link and video,
//  down to tuck it away; tap the header to toggle.
//

import AppKit
import SwiftUI

struct QueueTray: View {
    let jobs: [DownloadJob]
    let status: String
    let onCancelAll: () -> Void
    let onRemove: (UUID) -> Void
    let onRetry: (UUID) -> Void
    let onRetryAll: () -> Void
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

    @State private var settled: CGFloat = QueueTray.peek
    @State private var collapsed: Set<UUID> = []
    @GestureState private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var summary: QueueSummary { QueueSummary(jobs: jobs) }
    private var active: Bool { summary.isActive }
    private var running: DownloadJob? { jobs.first { $0.state == .running } }
    private var failedJobs: Int { jobs.filter { $0.state == .failed }.count }

    private var height: CGFloat { min(Self.full, max(Self.peek, settled - drag)) }

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
        .downerDockGlass()
        .onChange(of: height) { _, _ in
            expansion = min(1, max(0, (height - Self.peek) / (Self.list - Self.peek)))
        }
        .animation(Motion.standard(reduce: reduceMotion), value: settled)
        .onAppear { if startsOpen { settled = Self.list } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Download queue")
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
            .accessibilityHint("Drag or activate to show or hide every download")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggle() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            Button(action: active ? onCancelAll : onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(GlassCircleButtonStyle(size: 30))
            .help(active ? "Cancel all downloads" : "Clear")
            .accessibilityLabel(active ? "Cancel all downloads" : "Clear finished downloads")
            ring
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onTapGesture(perform: toggle)
        .motion(Motion.quick, value: subtitle)
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 4)
            Circle()
                .trim(from: 0, to: active ? max(0.02, summary.overall) : 1)
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(ringLabel)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .contentTransition(.numericText())
        }
        .frame(width: 44, height: 44)
        .motion(value: summary.overall)
        .accessibilityElement()
        .accessibilityLabel("Overall progress")
        .accessibilityValue(ringLabel)
    }

    private var progressBar: some View {
        VStack(spacing: 7) {
            DownerProgressBar(value: active ? max(0.01, summary.overall) : 1, tint: tint)
            HStack {
                Text(leftLabel)
                Spacer()
                if let speed = running?.speed { Text(speed) }
            }
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
            .motion(Motion.quick, value: leftLabel)
        }
        .padding(.horizontal, 4)
        .padding(.top, 10)
    }

    private var currentLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .symbolEffect(.pulse, isActive: active)
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
                    ForEach(jobs) { job in
                        if job.isPlaylist {
                            PlaylistSection(
                                job: job,
                                isCollapsed: collapsed.contains(job.id),
                                onToggle: { toggleCollapse(job.id) },
                                onRemove: { onRemove(job.id) },
                                onRetry: { onRetry(job.id) })
                        } else {
                            JobRow(job: job, onRemove: { onRemove(job.id) }, onRetry: { onRetry(job.id) })
                                .id(job.id.uuidString)
                        }
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
            .onChange(of: reveal > 0.5) { _, open in
                // opening the tray brings the video that is downloading into view
                guard open, let target = scrollTarget else { return }
                withAnimation(Motion.standard(reduce: reduceMotion)) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target, reveal > 0.5 else { return }
                withAnimation(Motion.standard(reduce: reduceMotion)) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
            .onChange(of: active) { _, nowActive in
                // when the queue ends, bring the first failure into view
                guard !nowActive, let failed = firstFailureID else { return }
                withAnimation(Motion.standard(reduce: reduceMotion)) {
                    proxy.scrollTo(failed, anchor: .center)
                }
            }
        }
        .padding(.top, 8)
        .allowsHitTesting(reveal > 0.6)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if active {
                Button("Cancel All", action: onCancelAll)
                    .buttonStyle(DownloadButtonStyle(isCancel: true, height: 46))
            } else {
                Button(action: onReveal) {
                    Label("Show in Finder", systemImage: "folder")
                }
                .buttonStyle(DownloadButtonStyle(height: 46))
                if summary.failedUnits > 0 || failedJobs > 0 {
                    Button(action: onRetryAll) {
                        Label("Retry failed", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(DownloadButtonStyle(isCancel: true, height: 46))
                }
            }
        }
        .padding(.top, 10)
        .allowsHitTesting(reveal > 0.6)
        .motion(value: active)
    }

    // MARK: Text
    private var title: String {
        if jobs.count == 1 { return jobs[0].displayTitle }
        return "Download queue"
    }

    private var subtitle: String {
        let s = summary
        var text = "\(s.doneUnits) of \(s.units) downloaded"
        if jobs.count > 1 { text += " · \(jobs.count) links" }
        let failed = max(s.failedUnits, failedJobs)
        if !active, failed > 0 { text += " · \(failed) failed" }
        return text
    }

    private var leftLabel: String {
        let s = summary
        if active {
            if let position = s.currentPosition { return "Download \(position) of \(s.units)" }
            return "Checking links…"
        }
        let failed = max(s.failedUnits, failedJobs)
        if jobs.allSatisfy({ $0.state == .cancelled }) { return "Cancelled" }
        return failed == 0 ? "All \(s.units) downloaded" : "\(failed) failed"
    }

    private var currentTitle: String {
        if active, let job = running {
            if let playlist = job.playlist, let current = playlist.current {
                return playlist.items[current - 1].title ?? "Item \(current)"
            }
            return job.displayTitle
        }
        return active ? status : status
    }

    private var ringLabel: String {
        active ? "\(Int((summary.overall * 100).rounded()))%" : "\(summary.doneUnits)/\(summary.units)"
    }

    private var tint: Color {
        if active { return Brand.red }
        return max(summary.failedUnits, failedJobs) == 0 ? .green : .orange
    }

    private var dotColor: Color {
        active ? .orange : (max(summary.failedUnits, failedJobs) == 0 ? .green : .orange)
    }

    // MARK: Scrolling
    private var scrollTarget: String? {
        guard let job = running else { return nil }
        if let current = job.playlist?.current { return "\(job.id.uuidString)-\(current)" }
        return job.id.uuidString
    }

    private var firstFailureID: String? {
        for job in jobs {
            if let item = job.playlist?.failed.first { return "\(job.id.uuidString)-\(item.id)" }
            if job.state == .failed { return job.id.uuidString }
        }
        return nil
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

    private func toggleCollapse(_ id: UUID) {
        withAnimation(Motion.standard(reduce: reduceMotion)) {
            if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
        }
    }
}

// MARK: - Rows

/// A single video's row.
private struct JobRow: View {
    let job: DownloadJob
    let onRemove: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            StateIcon(state: job.state, fraction: job.fraction)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(job.displayTitle)
                    .font(.system(size: 14, weight: job.state == .running ? .semibold : .medium))
                    .foregroundStyle(job.state == .queued ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 4)
        .frame(height: 52)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
        .motion(Motion.quick, value: job.state)
        .motion(value: job.fraction)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var trailing: some View {
        switch job.state {
        case .running:
            Text("\(Int((job.fraction * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .contentTransition(.numericText())
            RemoveButton(label: "Cancel", action: onRemove)
        case .queued:
            RemoveButton(label: "Remove from queue", action: onRemove)
        case .failed, .cancelled:
            Button("Retry", action: onRetry).buttonStyle(PillButtonStyle())
        case .done:
            EmptyView()
        }
    }

    private var detail: String {
        switch job.state {
        case .done: return "Downloaded"
        case .running:
            return job.speed.map { "Downloading · \($0)" } ?? "Downloading"
        case .queued: return job.isResolving ? "Checking link…" : "Waiting"
        case .failed: return job.detail ?? "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

/// A playlist: a header for the link, then one row per video.
private struct PlaylistSection: View {
    let job: DownloadJob
    let isCollapsed: Bool
    let onToggle: () -> Void
    let onRemove: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Brand.red)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(job.displayTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(summary)
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 8)
                    if job.state == .queued { RemoveButton(label: "Remove from queue", action: onRemove) }
                    if job.state == .failed || job.state == .cancelled {
                        Button("Retry", action: onRetry).buttonStyle(PillButtonStyle())
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                }
                .padding(.horizontal, 4)
                .frame(height: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottom) { Divider().opacity(0.5) }
            .accessibilityLabel("\(job.displayTitle), playlist")
            .accessibilityHint(isCollapsed ? "Show videos" : "Hide videos")

            if !isCollapsed, let playlist = job.playlist {
                ForEach(playlist.items) { item in
                    PlaylistRow(item: item, onRetry: onRetry)
                        .padding(.leading, 18)
                        .id("\(job.id.uuidString)-\(item.id)")
                        .transition(.opacity)
                }
            }
        }
        .motion(Motion.quick, value: job.state)
    }

    private var summary: String {
        guard let playlist = job.playlist else { return "Playlist" }
        switch job.state {
        case .running:
            return playlist.current.map { "Playlist · item \($0) of \(playlist.total)" } ?? "Playlist"
        case .queued: return "Playlist · \(playlist.total) videos · waiting"
        case .cancelled: return "Playlist · cancelled"
        default:
            let failed = playlist.failed.count
            return "Playlist · \(playlist.doneCount) of \(playlist.total) downloaded"
                + (failed > 0 ? " · \(failed) failed" : "")
        }
    }
}

private struct PlaylistRow: View {
    let item: PlaylistItem
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            StateIcon(
                state: {
                    switch item.state {
                    case .queued: return .queued
                    case .running: return .running
                    case .done: return .done
                    case .failed: return .failed
                    }
                }(),
                fraction: item.fraction
            )
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
            }
            Spacer(minLength: 8)
            if item.state == .failed {
                Button("Retry", action: onRetry).buttonStyle(PillButtonStyle())
            } else if item.state == .running {
                Text("\(Int((item.fraction * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 50)
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
        .motion(Motion.quick, value: item.state)
        .motion(value: item.fraction)
        .accessibilityElement(children: .combine)
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

private struct StateIcon: View {
    let state: DownloadJob.State
    let fraction: Double

    var body: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: state)
        case .running:
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.03, fraction))
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
        case .cancelled:
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
        }
    }
}

private struct RemoveButton: View {
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(hovering ? 0.16 : 0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .motion(Motion.quick, value: hovering)
    }
}
