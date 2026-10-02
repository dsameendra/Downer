//
//  SpringDriver.swift
//  Downer
//
//  Runs a CriticallyDampedSpring frame by frame, in step with the display. Unlike a SwiftUI
//  animation, the current value is always known, so a new gesture can grab the content
//  mid-settle and carry on from exactly where it is, with its speed.
//

import AppKit
import QuartzCore

@MainActor
final class SpringDriver: NSObject {
    private var spring: CriticallyDampedSpring?
    private var start: CFTimeInterval = 0
    private var link: CADisplayLink?

    /// The most recent value handed to `onUpdate`.
    private(set) var value: CGFloat = 0
    var onUpdate: (CGFloat) -> Void = { _ in }
    /// Called once when a settle reaches its target (not when stopped by a new gesture).
    var onFinish: () -> Void = {}
    var isRunning: Bool { spring != nil }

    func animate(from origin: CGFloat, to target: CGFloat, velocity: CGFloat, stiffness: CGFloat = 220) {
        spring = CriticallyDampedSpring(from: origin, to: target, velocity: velocity, stiffness: stiffness)
        value = origin
        start = CACurrentMediaTime()
        if link == nil {
            let displayLink = (NSScreen.main ?? NSScreen.screens[0]).displayLink(target: self, selector: #selector(tick(_:)))
            displayLink.add(to: .main, forMode: .common)
            link = displayLink
        }
    }

    /// Stops and returns the value on screen, so a gesture can take over from it.
    @discardableResult
    func stop() -> CGFloat {
        spring = nil
        link?.invalidate()
        link = nil
        return value
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let spring else { stop(); return }
        let t = CACurrentMediaTime() - start
        if spring.isSettled(at: t) {
            value = spring.target
            onUpdate(value)
            stop()
            onFinish()
        } else {
            value = spring.position(at: t)
            onUpdate(value)
        }
    }

    deinit {
        MainActor.assumeIsolated { link?.invalidate() }
    }
}
