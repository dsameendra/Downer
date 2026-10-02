//
//  TrackpadScroll.swift
//  Downer
//
//  Turns two-finger trackpad swipes into gestures. A two-finger swipe is a *scroll*
//  event, which SwiftUI's DragGesture never sees, so this watches `.scrollWheel`
//  events that land inside a region. At the start of each swipe it asks the view
//  whether to take it (so lists keep scrolling normally); if taken, the fingers
//  drive the view 1:1 and the momentum that follows is swallowed.
//

import AppKit
import SwiftUI

enum SwipeAxis { case horizontal, vertical }

/// What the fingers are doing at the start of a swipe.
struct ScrollIntent {
    var axis: SwipeAxis
    var right: CGFloat
    var up: CGFloat
}

struct TrackpadScrollHandlers {
    /// Called once per swipe, after a couple of points of movement. Return true to take it.
    var decide: (ScrollIntent) -> Bool = { _ in false }
    var began: () -> Void = {}
    /// Finger movement since the last call: `right` and `up` are positive in those directions.
    var changed: (_ right: CGFloat, _ up: CGFloat, _ time: TimeInterval) -> Void = { _, _, _ in }
    var ended: (_ time: TimeInterval) -> Void = { _ in }
    /// A mouse wheel notch (no fingers on a trackpad). Return true to take it.
    var discrete: (_ right: CGFloat, _ up: CGFloat) -> Bool = { _, _ in false }
    /// The Esc key. Return true if it was used.
    var escape: () -> Bool = { false }
}

/// Place as a `.background` of the area that should react. It never takes clicks.
struct TrackpadScrollRegion: NSViewRepresentable {
    var handlers: TrackpadScrollHandlers

    func makeNSView(context: Context) -> ScrollRegionView {
        let view = ScrollRegionView()
        view.handlers = handlers
        return view
    }

    func updateNSView(_ view: ScrollRegionView, context: Context) {
        view.handlers = handlers
    }
}

final class ScrollRegionView: NSView {
    var handlers = TrackpadScrollHandlers()

    private var monitor: Any?
    private var keyMonitor: Any?
    private var owned = false
    private var swallowMomentum = false
    private var pending = false
    private var accumulated = CGPoint.zero
    private var lastTime: TimeInterval = 0

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event) ?? event
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, event.keyCode == 53,
                event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
            else { return event }
            return self.handlers.escape() ? nil : event
        }
    }

    deinit { removeMonitor() }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        monitor = nil
        keyMonitor = nil
    }

    private func inside(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, !isHiddenOrHasHiddenAncestor else { return false }
        return bounds.contains(convert(event.locationInWindow, from: nil))
    }

    private func finger(_ event: NSEvent) -> (right: CGFloat, up: CGFloat) {
        ScrollConvention.finger(
            dx: event.scrollingDeltaX, dy: event.scrollingDeltaY,
            invertedFromDevice: event.isDirectionInvertedFromDevice)
    }

    /// Returns nil to consume the event, or the event to let it carry on.
    private func handle(_ event: NSEvent) -> NSEvent? {
        // a mouse wheel: one discrete step per notch
        guard event.hasPreciseScrollingDeltas else {
            guard inside(event) else { return event }
            let f = finger(event)
            return handlers.discrete(f.right, f.up) ? nil : event
        }

        // momentum after the fingers lift: ours to swallow if we owned the swipe
        if event.momentumPhase != [] {
            if swallowMomentum {
                if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) { swallowMomentum = false }
                return nil
            }
            return event
        }

        let phase = event.phase
        if phase.contains(.mayBegin) { return event }

        if phase.contains(.began) {
            guard inside(event) else { owned = false; pending = false; return event }
            owned = false
            swallowMomentum = false
            pending = true
            accumulated = .zero
            lastTime = event.timestamp
        }

        if phase.contains(.began) || phase.contains(.changed) {
            let f = finger(event)
            if owned {
                handlers.changed(f.right, f.up, event.timestamp)
                lastTime = event.timestamp
                return nil
            }
            if pending {
                accumulated.x += f.right
                accumulated.y += f.up
                if hypot(accumulated.x, accumulated.y) >= 2 {
                    pending = false
                    let intent = ScrollIntent(
                        axis: abs(accumulated.y) > abs(accumulated.x) ? .vertical : .horizontal,
                        right: accumulated.x, up: accumulated.y)
                    if handlers.decide(intent) {
                        owned = true
                        handlers.began()
                        handlers.changed(accumulated.x, accumulated.y, event.timestamp)
                        lastTime = event.timestamp
                        return nil
                    }
                }
            }
            return event
        }

        if phase.contains(.ended) || phase.contains(.cancelled) {
            pending = false
            if owned {
                owned = false
                swallowMomentum = true  // the system may still send coasting events
                handlers.ended(event.timestamp)
                return nil
            }
        }
        return event
    }
}

// MARK: - Reading a SwiftUI list's scroll position

/// Put as a `.background` inside a `ScrollView`'s content. Lets code outside ask whether the
/// list is scrolled to its top (so a pull-down can hand over to the sheet).
final class ScrollProbe {
    fileprivate weak var view: NSView?

    var debugOffset: String {
        guard let sv = view?.enclosingScrollView, let doc = sv.documentView else { return "no scroll view" }
        return "clip=\(sv.contentView.bounds) doc=\(doc.bounds) flipped=\(doc.isFlipped)"
    }

    var isAtTop: Bool {
        guard let scrollView = view?.enclosingScrollView, let document = scrollView.documentView else { return true }
        let clip = scrollView.contentView.bounds
        return document.isFlipped
            ? clip.minY <= document.bounds.minY + 1
            : clip.maxY >= document.bounds.maxY - 1
    }
}

struct ScrollProbeView: NSViewRepresentable {
    let probe: ScrollProbe

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        probe.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { probe.view = view }
}
