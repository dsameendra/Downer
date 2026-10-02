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
    let onRevealJob: (UUID) -> Void
    let onMove: (UUID, Int) -> Void
    let onDismiss: () -> Void
    /// 0 when peeking … 1 when fully open. The window behind dims with it.
    @Binding var expansion: CGFloat
    /// Opens the tray at launch; used for previews and tests.
    var startsOpen = false
    /// True when the panel shows the queue; false when it shows the single-download dock. Same glass
    /// either way: switching animates its height and cross-fades the contents, so it truly morphs.
    var isTray = true
    /// The dock's contents (its own padding included), shown while `isTray` is false.
    var dock: AnyView = AnyView(EmptyView())

    private static let peek: CGFloat = 162
    private static let list: CGFloat = 452
    private static let full: CGFloat = 604
    private static let detents: [CGFloat] = [peek, list, full]

    /// The panel's height on screen. Driven by the fingers while they are down, and by `driver` after.
    @State private var height: CGFloat = QueueTray.peek
    /// How tall the dock's contents want to be.
    @State private var dockHeight: CGFloat = 130
    @State private var pan = SnapPan(
        points: QueueTray.detents, rubberRange: 40, decelerationRate: Motion.deceleration)
    @State private var panStart: CGFloat = QueueTray.peek
    @State private var lastTranslation: CGFloat?
    @State private var driver = SpringDriver()
    @State private var probe = ScrollProbe()
    @State private var openRow: UUID?
    @State private var reorder: RowReorder?
    @State private var lifted: UUID?
    @State private var rowHeights: [UUID: CGFloat] = [:]
    @State private var collapsed: Set<UUID> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var summary: QueueSummary { QueueSummary(jobs: jobs) }
    private var active: Bool { summary.isActive }
    private var running: DownloadJob? { jobs.first { $0.state == .running } }
    private var failedJobs: Int { jobs.filter { $0.state == .failed }.count }

    /// 0…1 between the peeking and list heights; drives the cross-fade of content.
    private var reveal: CGFloat {
        min(1, max(0, (height - Self.peek) / (Self.list - Self.peek)))
    }

    var body: some View {
        ZStack(alignment: .top) {
            trayLayout
                .opacity(isTray ? 1 : 0)
                .animation(reduceMotion ? Motion.reduced : .easeIn(duration: 0.18).delay(0.07), value: isTray)
                .allowsHitTesting(isTray)
            dock
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: DockHeightKey.self, value: proxy.size.height)
                    }
                )
                .opacity(isTray ? 0 : 1)
                .animation(reduceMotion ? Motion.reduced : .easeOut(duration: 0.1), value: isTray)
                .allowsHitTesting(!isTray)
        }
        .frame(height: height, alignment: .top)
        .background(TrackpadScrollRegion(handlers: scrollHandlers))
        .downerDockGlass()
        .onPreferenceChange(DockHeightKey.self) { measured in
            dockHeight = measured
            if !isTray, !driver.isRunning { withAnimation(Motion.standard(reduce: reduceMotion)) { height = measured } }
        }
        .onChange(of: height) { _, _ in
            expansion = min(1, max(0, (height - Self.peek) / (Self.list - Self.peek)))
        }
        .onChange(of: isTray) { _, tray in
            // the same glass grows into the tray, or shrinks back into the dock
            let current = driver.isRunning ? driver.stop() : height
            height = current
            let target = tray ? Self.peek : dockHeight
            if reduceMotion {
                withAnimation(Motion.reduced) { height = target }
            } else {
                driver.animate(from: current, to: target, velocity: 0)
            }
        }
        .onAppear {
            driver.onUpdate = { height = $0 }
            height = isTray ? (startsOpen ? Self.list : Self.peek) : dockHeight
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Download queue")
    }

    // MARK: Pieces
    private var trayLayout: some View {
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
    }

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
            .accessibilityAction(named: "Expand download list") { animate(to: Self.list) }
            .accessibilityAction(named: "Collapse download list") { animate(to: Self.peek) }
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

    /// What a swipe on this row offers. The last action is what a full swipe does.
    private func swipeActions(for job: DownloadJob) -> [SwipeAction] {
        let remove = SwipeAction(
            id: "remove", title: job.state == .running ? "Cancel" : (job.isFinished ? "Clear" : "Remove"),
            systemImage: job.state == .running ? "xmark" : "trash", tint: .red,
            handler: { onRemove(job.id) })
        switch job.state {
        case .queued, .running:
            return [remove]
        case .failed, .cancelled:
            return [SwipeAction(id: "retry", title: "Retry", systemImage: "arrow.clockwise", tint: .orange,
                                handler: { onRetry(job.id) }), remove]
        case .done:
            return [SwipeAction(id: "reveal", title: "Show", systemImage: "folder", tint: .blue,
                                handler: { onRevealJob(job.id) }), remove]
        }
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                        let open = openRow == job.id
                        let setOpen: (Bool) -> Void = { isOpen in
                            if isOpen { openRow = job.id } else if openRow == job.id { openRow = nil }
                        }
                        Group {
                            if job.isPlaylist {
                                PlaylistSection(
                                    job: job,
                                    isCollapsed: collapsed.contains(job.id),
                                    actions: swipeActions(for: job),
                                    isOpen: open,
                                    onOpenChange: setOpen,
                                    onToggle: { toggleCollapse(job.id) },
                                    onRemove: { onRemove(job.id) },
                                    onRetry: { onRetry(job.id) })
                            } else {
                                SwipeActionsRow(actions: swipeActions(for: job), isOpen: open, onOpenChange: setOpen) {
                                    JobRow(job: job, onRemove: { onRemove(job.id) }, onRetry: { onRetry(job.id) })
                                }
                            }
                        }
                        .modifier(
                            ReorderableRow(
                                id: job.id,
                                shift: reorder?.shift(for: index) ?? 0,
                                isLifted: lifted == job.id,
                                isActive: reorder != nil,
                                isMovable: job.state == .queued && !job.isResolving,
                                position: reorderPosition(of: index),
                                onBegin: { beginReorder(job.id) },
                                onDrag: { moveReorder($0) },
                                onEnd: { endReorder() },
                                onStep: { step in stepReorder(job.id, by: step) }))
                        .id(job.id.uuidString)
                    }
                }
                .padding(.top, 6)
                .background(ScrollProbeView(probe: probe))
            }
            .onPreferenceChange(RowHeightKey.self) { rowHeights = $0 }
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
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private var scrollHandlers: TrackpadScrollHandlers {
        var h = TrackpadScrollHandlers()
        // a vertical swipe belongs to the tray unless the list underneath should scroll
        h.decide = { intent in
            guard isTray, intent.axis == .vertical else { return false }
            debugLog("decide height=\(height) atTop=\(probe.isAtTop) up=\(intent.up) offset=\(probe.debugOffset)")
            return SheetScrollArbiter.owner(
                sheetHeight: height, fullHeight: Self.full, listVisible: height > Self.peek + 1,
                listAtTop: probe.isAtTop, fingerUp: intent.up) == .sheet
        }
        h.began = { beginPan(at: now) }
        h.changed = { _, up, time in movePan(by: up, at: time) }
        h.ended = { time in endPan(at: time) }
        // a mouse wheel notch steps one position
        h.discrete = { _, up in
            guard isTray, abs(up) > 0.01 else { return false }
            if driver.isRunning { return true }  // swallow notches while it is settling
            let owner = SheetScrollArbiter.owner(
                sheetHeight: height, fullHeight: Self.full, listVisible: height > Self.peek + 1,
                listAtTop: probe.isAtTop, fingerUp: up)
            guard owner == .sheet else { return false }
            let next = up > 0 ? Self.detents.first { $0 > height + 1 } : Self.detents.last { $0 < height - 1 }
            guard let next else { return true }
            animate(to: next)
            Haptics.tick()
            return true
        }
        // Esc folds the tray away
        h.escape = {
            guard isTray, height > Self.peek + 1 else { return false }
            animate(to: Self.peek)
            return true
        }
        return h
    }

    /// Mouse and pen dragging on the handle or header, feeding the same model as the trackpad.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if lastTranslation == nil {
                    beginPan(at: now)
                    lastTranslation = 0
                }
                let delta = -(value.translation.height - (lastTranslation ?? 0))
                lastTranslation = value.translation.height
                movePan(by: delta, at: now)
            }
            .onEnded { _ in
                lastTranslation = nil
                endPan(at: now)
            }
    }

    #if DEBUG
        private func debugLog(_ line: String) {
            guard ProcessInfo.processInfo.environment["DOWNER_GESTURE_LOG"] != nil else { return }
            let url = URL(fileURLWithPath: "/tmp/claude-501/downer-gesture.log")
            let data = (line + "\n").data(using: .utf8)!
            if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(data); try? handle.close() }
            else { try? data.write(to: url) }
        }
    #else
        private func debugLog(_ line: String) {}
    #endif

    private func beginPan(at time: TimeInterval) {
        let current = driver.isRunning ? driver.stop() : height  // grab it where it is
        height = current
        panStart = current
        pan.begin(at: current, time: time)
    }

    private func movePan(by delta: CGFloat, at time: TimeInterval) {
        debugLog("move delta=\(delta) t=\(time) raw→\(pan.raw + delta)")
        pan.move(by: delta, at: time)
        height = pan.value  // 1:1 with the fingers, no animation
    }

    private func endPan(at time: TimeInterval) {
        let settle = pan.settle(at: time)
        debugLog("end t=\(time) value=\(pan.value) settle=\(settle)")
        run(settle)
        if abs(settle.target - panStart) > 1 { Haptics.tick() }
    }

    private func run(_ settle: SnapPan.Settle) {
        if reduceMotion {
            driver.stop()
            withAnimation(Motion.reduced) { height = settle.target }
        } else {
            driver.animate(from: height, to: settle.target, velocity: settle.velocity)
        }
    }

    private func animate(to target: CGFloat) {
        let current = driver.isRunning ? driver.stop() : height
        height = current
        run(SnapPan.Settle(target: target, velocity: 0, normalizedVelocity: 0))
    }

    private func toggle() {
        animate(to: height > Self.peek + 1 ? Self.peek : Self.list)
    }

    // MARK: Reordering
    /// "2 of 4" among the waiting links, for VoiceOver.
    private func reorderPosition(of index: Int) -> (index: Int, count: Int)? {
        let waiting = jobs.indices.filter { jobs[$0].state == .queued && !jobs[$0].isResolving }
        guard let place = waiting.firstIndex(of: index) else { return nil }
        return (place, waiting.count)
    }

    private func beginReorder(_ id: UUID) {
        guard reorder == nil, let source = jobs.firstIndex(where: { $0.id == id }),
            let bounds = QueueOrder.movableBlock(waiting: jobs.map { $0.state == .queued && !$0.isResolving }),
            bounds.contains(source)
        else { return }
        let heights = jobs.map { rowHeights[$0.id] ?? 52 }
        reorder = RowReorder(heights: heights, source: source, bounds: bounds)
        lifted = id
        openRow = nil
        Haptics.tick()
    }

    private func moveReorder(_ translation: CGFloat) {
        guard var model = reorder else { return }
        let before = model.target
        model.drag(to: translation)
        reorder = model
        if model.target != before { Haptics.tick() }
    }

    private func endReorder() {
        guard let model = reorder, let id = lifted else { return }
        withAnimation(Motion.standard(reduce: reduceMotion)) {
            reorder = nil
            lifted = nil
            if model.target != model.source { onMove(id, model.target) }
        }
    }

    /// Move up or down one place without dragging (VoiceOver and keyboard).
    private func stepReorder(_ id: UUID, by step: Int) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(Motion.standard(reduce: reduceMotion)) { onMove(id, index + step) }
        Haptics.tick()
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
    let actions: [SwipeAction]
    let isOpen: Bool
    let onOpenChange: (Bool) -> Void
    let onToggle: () -> Void
    let onRemove: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SwipeActionsRow(actions: actions, isOpen: isOpen, onOpenChange: onOpenChange) {
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
            }

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

private struct RowHeightKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Press and hold a waiting link, then drag it to change when it will download. The lifted row
/// follows the pointer; the others slide aside to make room.
private struct ReorderableRow: ViewModifier {
    let id: UUID
    let shift: CGFloat
    let isLifted: Bool
    let isActive: Bool
    let isMovable: Bool
    let position: (index: Int, count: Int)?
    let onBegin: () -> Void
    let onDrag: (CGFloat) -> Void
    let onEnd: () -> Void
    let onStep: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: RowHeightKey.self, value: [id: proxy.size.height])
                }
            )
            .scaleEffect(isLifted && !reduceMotion ? 1.025 : 1)
            .shadow(color: .black.opacity(isLifted ? 0.28 : 0), radius: isLifted ? 14 : 0, y: isLifted ? 6 : 0)
            .offset(y: shift)
            .zIndex(isLifted ? 1 : 0)
            // the lifted row follows the pointer exactly; the rest glide aside
            .animation(isLifted ? nil : Motion.standard(reduce: reduceMotion), value: shift)
            .animation(Motion.quick, value: isLifted)
            .simultaneousGesture(isMovable ? hold : nil)
            .modifier(MoveActions(position: isMovable ? position : nil, onStep: onStep))
    }

    private var hold: some Gesture {
        LongPressGesture(minimumDuration: 0.28)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !isActive { onBegin() }
                if let drag { onDrag(drag.translation.height) }
            }
            .onEnded { _ in onEnd() }
    }
}

private struct MoveActions: ViewModifier {
    let position: (index: Int, count: Int)?
    let onStep: (Int) -> Void

    func body(content: Content) -> some View {
        if let position {
            content
                .accessibilityAction(named: Text("Move up")) { if position.index > 0 { onStep(-1) } }
                .accessibilityAction(named: Text("Move down")) { if position.index < position.count - 1 { onStep(1) } }
        } else {
            content
        }
    }
}

private struct DockHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 130
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
