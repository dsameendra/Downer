//
//  GestureModels.swift
//  Downer
//
//  The maths behind every gesture, with no UI in it so it can be tested on its own:
//  rubber banding, velocity, snapping, who owns a scroll (sheet or list), row swipes
//  and reordering. Views feed these models input and draw whatever they report.
//

import CoreGraphics
import Foundation

// MARK: - Input conventions

enum ScrollConvention {
    /// Converts raw AppKit scroll deltas into *finger* directions, whatever the user's
    /// "Natural scrolling" setting: `right` is positive when the fingers move right,
    /// `up` is positive when they move up.
    static func finger(dx: CGFloat, dy: CGFloat, invertedFromDevice: Bool) -> (right: CGFloat, up: CGFloat) {
        invertedFromDevice ? (dx, -dy) : (-dx, dy)
    }
}

// MARK: - Rubber band

enum RubberBand {
    /// How far past a limit the content shows, for `overshoot` points of raw pull.
    /// Grows quickly at first, then resists, and never exceeds `range`.
    static func resist(_ overshoot: CGFloat, range: CGFloat, coefficient: CGFloat = 0.55) -> CGFloat {
        guard overshoot > 0, range > 0 else { return 0 }
        return (1 - 1 / (overshoot * coefficient / range + 1)) * range
    }
}

// MARK: - Velocity

/// Estimates how fast the fingers were moving at release, from the last ~100 ms.
struct VelocityTracker {
    private var samples: [(time: TimeInterval, position: CGFloat)] = []
    private let window: TimeInterval

    init(window: TimeInterval = 0.1) { self.window = window }

    mutating func reset() { samples.removeAll() }

    mutating func add(position: CGFloat, at time: TimeInterval) {
        samples.append((time, position))
        samples.removeAll { time - $0.time > window + 1e-9 }
    }

    /// Points per second. Zero if the fingers had stopped before lifting.
    func velocity(at time: TimeInterval) -> CGFloat {
        guard let first = samples.first, let last = samples.last, last.time > first.time else { return 0 }
        if time - last.time > 0.08 { return 0 }
        return (last.position - first.position) / CGFloat(last.time - first.time)
    }
}

// MARK: - Snapping pan

/// A value that follows the fingers and settles on one of several resting points.
/// Used for the tray height, the row swipe offset and the segmented-control thumb.
struct SnapPan {
    struct Settle: Equatable {
        var target: CGFloat
        /// Points per second at release.
        var velocity: CGFloat
        /// Velocity as a fraction of the distance still to travel, which is what a spring
        /// animation's `initialVelocity` expects.
        var normalizedVelocity: CGFloat
    }

    var points: [CGFloat]
    /// How far the value may be dragged outside `limits` (with resistance).
    var rubberRange: CGFloat
    var decelerationRate: CGFloat
    var limits: ClosedRange<CGFloat>

    private(set) var raw: CGFloat = 0
    private var tracker = VelocityTracker()

    init(points: [CGFloat], limits: ClosedRange<CGFloat>? = nil, rubberRange: CGFloat = 80, decelerationRate: CGFloat = 0.994) {
        let sorted = points.sorted()
        self.points = sorted
        self.limits = limits ?? (sorted.first ?? 0)...(sorted.last ?? 0)
        self.rubberRange = rubberRange
        self.decelerationRate = decelerationRate
    }

    /// The value to draw: the raw value, with resistance past the limits.
    var value: CGFloat { constrain(raw) }
    var isPastEdge: Bool { raw < limits.lowerBound || raw > limits.upperBound }

    func constrain(_ x: CGFloat) -> CGFloat {
        if x > limits.upperBound { return limits.upperBound + RubberBand.resist(x - limits.upperBound, range: rubberRange) }
        if x < limits.lowerBound { return limits.lowerBound - RubberBand.resist(limits.lowerBound - x, range: rubberRange) }
        return x
    }

    mutating func begin(at value: CGFloat, time: TimeInterval = 0) {
        raw = value
        tracker.reset()
        tracker.add(position: value, at: time)
    }

    mutating func move(by delta: CGFloat, at time: TimeInterval) {
        raw += delta
        tracker.add(position: raw, at: time)
    }

    /// Where the value would coast to if released with `velocity`.
    func projected(velocity: CGFloat) -> CGFloat {
        value + velocity / 1000 * decelerationRate / (1 - decelerationRate)
    }

    /// Release: choose the resting point nearest to where the motion would end.
    mutating func settle(at time: TimeInterval, velocity override: CGFloat? = nil) -> Settle {
        let v = override ?? tracker.velocity(at: time)
        let landing = projected(velocity: v)
        let target = points.min { abs($0 - landing) < abs($1 - landing) } ?? value
        let distance = target - value
        let normalized: CGFloat = abs(distance) < 0.5 ? 0 : v / distance
        raw = target
        return Settle(target: target, velocity: v, normalizedVelocity: normalized)
    }
}

// MARK: - Who owns a scroll?

enum ScrollOwner: Equatable { case sheet, list }

/// Gesture chaining, as with system sheets: the sheet grows before the list scrolls, and the
/// list scrolls back to its top before the sheet collapses. Decided once per gesture.
enum SheetScrollArbiter {
    static func owner(sheetHeight: CGFloat, fullHeight: CGFloat, listVisible: Bool, listAtTop: Bool, fingerUp: CGFloat) -> ScrollOwner {
        guard listVisible else { return .sheet }
        if fingerUp > 0 { return sheetHeight >= fullHeight - 0.5 ? .list : .sheet }
        if fingerUp < 0 { return listAtTop ? .sheet : .list }
        return .sheet
    }
}

// MARK: - Row swipe

/// A row that slides left to reveal actions, and commits its primary action on a long swipe.
struct SwipeReveal {
    enum Outcome: Equatable { case close, open, commit }

    let actionWidth: CGFloat
    let commitDistance: CGFloat
    private(set) var pan: SnapPan
    private(set) var crossedCommit = false

    init(actionWidth: CGFloat, rowWidth: CGFloat, commitFraction: CGFloat = 0.55) {
        self.actionWidth = actionWidth
        self.commitDistance = max(actionWidth * 1.4, rowWidth * commitFraction)
        self.pan = SnapPan(points: [-actionWidth, 0], limits: -rowWidth...0, rubberRange: 40)
    }

    /// Current offset: 0 is closed, negative is open.
    var offset: CGFloat { pan.value }

    mutating func begin(open: Bool, time: TimeInterval = 0) {
        begin(at: open ? -actionWidth : 0, time: time)
    }

    /// Start from wherever the row is on screen, e.g. grabbed in the middle of a settle.
    mutating func begin(at offset: CGFloat, time: TimeInterval = 0) {
        pan.begin(at: offset, time: time)
        crossedCommit = offset <= -commitDistance
    }

    /// Returns true on the move that crosses the commit threshold in either direction,
    /// so the caller can play a haptic tick once.
    @discardableResult
    mutating func move(by delta: CGFloat, at time: TimeInterval) -> Bool {
        pan.move(by: delta, at: time)
        let past = pan.raw <= -commitDistance
        defer { crossedCommit = past }
        return past != crossedCommit
    }

    mutating func end(at time: TimeInterval, velocity: CGFloat? = nil) -> (outcome: Outcome, settle: SnapPan.Settle) {
        if pan.raw <= -commitDistance {
            let settle = SnapPan.Settle(target: pan.limits.lowerBound, velocity: velocity ?? 0, normalizedVelocity: 0)
            return (.commit, settle)
        }
        let s = pan.settle(at: time, velocity: velocity)
        return (s.target == 0 ? .close : .open, s)
    }
}

// MARK: - Reordering

/// Maps a dragged row's offset to the slot it would drop into, and how far each other row
/// moves aside. Only rows inside `movable` take part.
struct ReorderModel {
    let rowHeight: CGFloat
    let count: Int
    let movable: ClosedRange<Int>
    let source: Int
    private(set) var dragOffset: CGFloat = 0

    init?(rowHeight: CGFloat, count: Int, movable: ClosedRange<Int>, source: Int) {
        guard movable.contains(source), movable.lowerBound >= 0, movable.upperBound < count, rowHeight > 0 else { return nil }
        self.rowHeight = rowHeight
        self.count = count
        self.movable = movable
        self.source = source
    }

    /// The dragged row never leaves the movable block.
    mutating func drag(to offset: CGFloat) {
        let minOffset = CGFloat(movable.lowerBound - source) * rowHeight
        let maxOffset = CGFloat(movable.upperBound - source) * rowHeight
        dragOffset = min(max(offset, minOffset), maxOffset)
    }

    var target: Int {
        let slots = Int((dragOffset / rowHeight).rounded())
        return min(max(source + slots, movable.lowerBound), movable.upperBound)
    }

    /// How far row `index` is pushed aside while the source row is dragged.
    func shift(for index: Int) -> CGFloat {
        guard index != source else { return dragOffset }
        if source < target, index > source, index <= target { return -rowHeight }
        if source > target, index < source, index >= target { return rowHeight }
        return 0
    }
}

// MARK: - Spring

/// A critically damped spring (no oscillation) solved exactly, so it can be sampled at any time
/// and started from any position and velocity. That is what makes a settle interruptible: grab the
/// content mid-animation and you hold exactly what is on screen.
struct CriticallyDampedSpring {
    let origin: CGFloat
    let target: CGFloat
    let omega: CGFloat
    private let a: CGFloat
    private let b: CGFloat

    /// `velocity` is in points per second. `stiffness` ≈ 220 settles in about 0.3 s.
    init(from origin: CGFloat, to target: CGFloat, velocity: CGFloat, stiffness: CGFloat = 220) {
        self.origin = origin
        self.target = target
        self.omega = stiffness.squareRoot()
        // A critically damped spring only overshoots if it starts faster than ω × the distance left.
        // Cap the launch speed just below that, so even a hard flick settles without a bounce.
        var v = velocity
        let distance = target - origin
        if distance != 0, v * distance > 0 {
            v = (v > 0 ? 1 : -1) * min(abs(v), omega * abs(distance) * 0.98)
        }
        self.a = origin - target
        self.b = v + omega * (origin - target)
    }

    func position(at t: TimeInterval) -> CGFloat {
        let t = CGFloat(t)
        return target + (a + b * t) * exp(-omega * t)
    }

    func velocity(at t: TimeInterval) -> CGFloat {
        let t = CGFloat(t)
        return (b - omega * (a + b * t)) * exp(-omega * t)
    }

    func isSettled(at t: TimeInterval) -> Bool {
        abs(position(at: t) - target) < 0.05 && abs(velocity(at: t)) < 0.5
    }
}

// MARK: - Swipe action layout

/// How the revealed action buttons share the space a row has been swiped open. Every button keeps its
/// width; on a long swipe the last one (the one a full swipe commits) stretches to fill what is left.
enum SwipeActionLayout {
    static func widths(count: Int, revealed: CGFloat, chip: CGFloat, spacing: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        let others = CGFloat(count - 1)
        let fixed = others * (chip + spacing)
        let last = max(chip, revealed - fixed)
        return Array(repeating: chip, count: count - 1) + [last]
    }

    /// Width needed to show every button at rest.
    static func restingWidth(count: Int, chip: CGFloat, spacing: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * chip + CGFloat(count - 1) * spacing
    }
}
