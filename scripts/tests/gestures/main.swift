// Tests for Downer/GestureModels.swift. Run with scripts/test-gestures.sh
import CoreGraphics
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    print(ok ? "PASS" : "FAIL", name, ok ? "" : detail())
    if !ok { failures += 1 }
}
func near(_ a: CGFloat, _ b: CGFloat, _ eps: CGFloat = 0.01) -> Bool { abs(a - b) <= eps }

// MARK: rubber band
check("rubber band: no overshoot, no displacement", RubberBand.resist(0, range: 80) == 0)
check("rubber band: stays under its range", RubberBand.resist(100_000, range: 80) < 80)
check("rubber band: monotonic", RubberBand.resist(50, range: 80) < RubberBand.resist(100, range: 80))
check("rubber band: resists (displays less than the pull)", RubberBand.resist(100, range: 80) < 100)

// MARK: input conventions
let natural = ScrollConvention.finger(dx: 10, dy: -10, invertedFromDevice: true)
check("natural scrolling: fingers up/right are positive", natural.up == 10 && natural.right == 10, "\(natural)")
let classic = ScrollConvention.finger(dx: -10, dy: 10, invertedFromDevice: false)
check("classic scrolling: fingers up/right are positive", classic.up == 10 && classic.right == 10, "\(classic)")

// MARK: velocity
var vt = VelocityTracker()
vt.add(position: 0, at: 1.00); vt.add(position: 100, at: 1.10)
check("velocity: 100 pt in 0.1 s is 1000 pt/s", near(vt.velocity(at: 1.10), 1000), "\(vt.velocity(at: 1.10))")
check("velocity: zero when the fingers rested before lifting", vt.velocity(at: 1.30) == 0)
var vt2 = VelocityTracker()
vt2.add(position: 0, at: 0); vt2.add(position: 500, at: 0.5); vt2.add(position: 510, at: 0.6)
check("velocity: only the last 100 ms count", near(vt2.velocity(at: 0.6), 100), "\(vt2.velocity(at: 0.6))")

// MARK: snap pan
func pan(_ points: [CGFloat] = [0, 100, 200]) -> SnapPan { SnapPan(points: points, rubberRange: 80) }
var p = pan(); p.begin(at: 0); p.move(by: 60, at: 0.1)
check("snap: slow drag past halfway goes to the next point", p.settle(at: 5, velocity: 0).target == 100)
p = pan(); p.begin(at: 0); p.move(by: 40, at: 0.1)
check("snap: slow drag short of halfway falls back", p.settle(at: 5, velocity: 0).target == 0)
p = pan(); p.begin(at: 0); p.move(by: 40, at: 0.1)
check("snap: a flick carries to the next point", p.settle(at: 0.1, velocity: 600).target == 100)
p = pan(); p.begin(at: 0); p.move(by: 40, at: 0.1)
check("snap: a hard flick skips a point", p.settle(at: 0.1, velocity: 2000).target == 200)
p = pan(); p.begin(at: 200); p.move(by: -40, at: 0.1)
check("snap: a downward flick works the other way", p.settle(at: 0.1, velocity: -2000).target == 0)
p = pan(); p.begin(at: 200); p.move(by: 200, at: 0.1)
check("snap: pulling past the end resists", p.value > 200 && p.value < 280 && p.isPastEdge, "\(p.value)")
p = pan(); p.begin(at: 0); p.move(by: -200, at: 0.1)
check("snap: pulling past the start resists", p.value < 0 && p.value > -80, "\(p.value)")
p = pan(); p.begin(at: 0); p.move(by: 60, at: 0.1)
let toward = p.settle(at: 0.1, velocity: 400)
check("snap: velocity toward the target is positive", toward.target == 100 && toward.normalizedVelocity > 0, "\(toward)")
p = pan(); p.begin(at: 0); p.move(by: 60, at: 0.1)
let still = p.settle(at: 5, velocity: 0)
check("snap: no velocity means a plain settle", still.normalizedVelocity == 0)

// MARK: scroll ownership
typealias A = SheetScrollArbiter
check("owner: peek is always the sheet", A.owner(sheetHeight: 162, fullHeight: 604, listVisible: false, listAtTop: true, fingerUp: 10) == .sheet)
check("owner: swipe up in the list detent grows the sheet", A.owner(sheetHeight: 452, fullHeight: 604, listVisible: true, listAtTop: true, fingerUp: 10) == .sheet)
check("owner: swipe up at full height scrolls the list", A.owner(sheetHeight: 604, fullHeight: 604, listVisible: true, listAtTop: true, fingerUp: 10) == .list)
check("owner: swipe down with the list scrolled scrolls the list", A.owner(sheetHeight: 604, fullHeight: 604, listVisible: true, listAtTop: false, fingerUp: -10) == .list)
check("owner: swipe down with the list at its top collapses the sheet", A.owner(sheetHeight: 604, fullHeight: 604, listVisible: true, listAtTop: true, fingerUp: -10) == .sheet)
check("owner: swipe down in the list detent, list scrolled, scrolls the list", A.owner(sheetHeight: 452, fullHeight: 604, listVisible: true, listAtTop: false, fingerUp: -10) == .list)

// MARK: row swipe
var sw = SwipeReveal(actionWidth: 144, rowWidth: 400)
check("swipe: commit distance is beyond the actions", sw.commitDistance >= 144 * 1.4 && near(sw.commitDistance, 220), "\(sw.commitDistance)")
sw.begin(open: false); sw.move(by: -60, at: 0.1)
check("swipe: a short slow pull closes again", sw.end(at: 5, velocity: 0).outcome == .close)
sw.begin(open: false); sw.move(by: -100, at: 0.1)
check("swipe: past halfway opens", sw.end(at: 5, velocity: 0).outcome == .open)
sw.begin(open: false); sw.move(by: -30, at: 0.1)
check("swipe: a quick flick left opens", sw.end(at: 0.1, velocity: -500).outcome == .open)
sw.begin(open: true); sw.move(by: 40, at: 0.1)
check("swipe: a small pull back leaves an open row open", sw.end(at: 5, velocity: 0).outcome == .open)
sw.begin(open: true); sw.move(by: 90, at: 0.1)
check("swipe: pulling an open row back past halfway closes it", sw.end(at: 5, velocity: 0).outcome == .close)
sw.begin(open: false)
let crossed1 = sw.move(by: -230, at: 0.1)
check("swipe: crossing the commit distance reports once", crossed1 == true)
check("swipe: moving further does not report again", sw.move(by: -10, at: 0.2) == false)
check("swipe: releasing past it commits", sw.end(at: 0.3, velocity: 0).outcome == .commit)
sw.begin(open: false); _ = sw.move(by: -230, at: 0.1)
check("swipe: backing out reports the crossing again", sw.move(by: 60, at: 0.2) == true)
check("swipe: backing out then releasing does not commit", sw.end(at: 5, velocity: 0).outcome != .commit)
sw.begin(open: false); sw.move(by: 90, at: 0.1)
check("swipe: pulling right resists and snaps closed", sw.offset > 0 && sw.offset < 40 && sw.end(at: 5, velocity: 0).outcome == .close, "\(sw.offset)")

// MARK: reorder
var r = ReorderModel(rowHeight: 52, count: 6, movable: 2...5, source: 3)!
r.drag(to: 25); check("reorder: under half a row stays", r.target == 3)
r.drag(to: 27); check("reorder: over half a row moves one slot", r.target == 4)
r.drag(to: 200); check("reorder: clamps to the end of the movable block", r.target == 5 && r.dragOffset == 104, "\(r.target) \(r.dragOffset)")
r.drag(to: -200); check("reorder: clamps to the start of the movable block", r.target == 2 && r.dragOffset == -52, "\(r.target) \(r.dragOffset)")
r.drag(to: 104)
check("reorder: rows between source and target move up", r.shift(for: 4) == -52 && r.shift(for: 5) == -52 && r.shift(for: 2) == 0)
check("reorder: the dragged row follows the finger", r.shift(for: 3) == 104)
r.drag(to: -52)
check("reorder: dragging up pushes the row above down", r.shift(for: 2) == 52 && r.shift(for: 4) == 0)
check("reorder: rows outside the movable block never move", r.shift(for: 0) == 0 && r.shift(for: 1) == 0)
check("reorder: a source outside the movable block is rejected", ReorderModel(rowHeight: 52, count: 6, movable: 2...5, source: 1) == nil)

// MARK: spring
let sp = CriticallyDampedSpring(from: 100, to: 400, velocity: 600)
check("spring: starts where it was released", near(sp.position(at: 0), 100))
check("spring: starts at the release velocity", near(sp.velocity(at: 0), 600, 0.5), "\(sp.velocity(at: 0))")
check("spring: arrives at the target", near(sp.position(at: 1.5), 400, 0.05), "\(sp.position(at: 1.5))")
check("spring: settles quickly (under 0.7 s)", sp.isSettled(at: 0.7) || near(sp.position(at: 0.7), 400, 2), "\(sp.position(at: 0.7))")
let slow = CriticallyDampedSpring(from: 100, to: 400, velocity: 0)
var monotonic = true; var prev = slow.position(at: 0)
for i in 1...100 { let x = slow.position(at: Double(i) * 0.01); if x < prev - 0.0001 { monotonic = false }; prev = x }
check("spring: from rest it never overshoots or bounces", monotonic && prev <= 400.0001)
let away = CriticallyDampedSpring(from: 100, to: 400, velocity: -500)
check("spring: a velocity away from the target still arrives", near(away.position(at: 2.0), 400, 0.05))
check("spring: continuity, position is the integral of velocity", near((sp.position(at: 0.2001) - sp.position(at: 0.2)) / 0.0001, sp.velocity(at: 0.2), 2))

var maxPos: CGFloat = 0
let hard = CriticallyDampedSpring(from: 452, to: 604, velocity: 6000)
for i in 0...400 { maxPos = max(maxPos, hard.position(at: Double(i) * 0.005)) }
check("spring: a hard flick toward the target never overshoots it", maxPos <= 604.0001, "\(maxPos)")
let hardDown = CriticallyDampedSpring(from: 604, to: 162, velocity: -9000)
var minPos: CGFloat = 1000
for i in 0...400 { minPos = min(minPos, hardDown.position(at: Double(i) * 0.005)) }
check("spring: a hard flick downward never undershoots", minPos >= 161.9999, "\(minPos)")
check("spring: a flick that is not too hard keeps its speed", near(CriticallyDampedSpring(from: 0, to: 1000, velocity: 800).velocity(at: 0), 800, 0.5))

print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
