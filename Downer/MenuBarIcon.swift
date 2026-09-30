//
//  MenuBarIcon.swift
//  Downer
//
//  The menu bar glyph: the app icon's double chevron, with a progress ring while
//  a download runs, a check when it finishes, and an orange dot when something
//  needs attention. Drawn in code so every state stays crisp at any scale.
//

import AppKit

enum MenuBarIcon {
    enum State: Equatable {
        case idle
        /// nil = running but no percentage yet
        case progress(Double?)
        case done
        case attention
    }

    static func image(for state: State, size: CGFloat = 20) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            draw(state, in: rect)
            return true
        }
        // The attention dot is orange, so that state cannot be a template image.
        image.isTemplate = state != .attention
        image.accessibilityDescription = description(of: state)
        return image
    }

    static func description(of state: State) -> String {
        switch state {
        case .idle: return "Downer"
        case .progress(let value):
            return value.map { "Downer, downloading, \(Int(($0 * 100).rounded())) percent" } ?? "Downer, downloading"
        case .done: return "Downer, download completed"
        case .attention: return "Downer, needs attention"
        }
    }

    // MARK: Drawing (22-unit grid, y down, like the design mock)
    private static func draw(_ state: State, in rect: NSRect) {
        let scale = rect.width / 22
        let ink = state == .attention ? NSColor.labelColor : NSColor.black

        let transform = NSAffineTransform()
        transform.scale(by: scale)
        transform.concat()

        ink.setStroke()
        switch state {
        case .idle, .attention:
            chevrons(width: 2)
            if state == .attention {
                NSColor.systemOrange.setFill()
                NSBezierPath(ovalIn: NSRect(x: 14.4, y: 14.4, width: 6.4, height: 6.4)).fill()
            }
        case .progress(let value):
            ring(fraction: 1, alpha: 0.28)
            ring(fraction: value ?? 0.25, alpha: 1)
            let inner = NSAffineTransform()
            inner.translateX(by: 11, yBy: 11)
            inner.scale(by: 0.58)
            inner.translateX(by: -11, yBy: -10.6)
            NSGraphicsContext.saveGraphicsState()
            inner.concat()
            chevrons(width: 2.2)
            NSGraphicsContext.restoreGraphicsState()
        case .done:
            ring(fraction: 1, alpha: 1)
            let check = NSBezierPath()
            check.lineWidth = 2
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.move(to: NSPoint(x: 6.8, y: 11.4))
            check.line(to: NSPoint(x: 9.8, y: 14.4))
            check.line(to: NSPoint(x: 15.4, y: 8.2))
            check.stroke()
        }
    }

    private static func chevrons(width: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: 6, y: 5.2))
        path.line(to: NSPoint(x: 11, y: 9.8))
        path.line(to: NSPoint(x: 16, y: 5.2))
        path.move(to: NSPoint(x: 6, y: 11.4))
        path.line(to: NSPoint(x: 11, y: 16))
        path.line(to: NSPoint(x: 16, y: 11.4))
        path.stroke()
    }

    /// Clockwise from 12 o'clock. The grid is y-down, so "clockwise" is the flipped sense.
    private static func ring(fraction: Double, alpha: CGFloat) {
        let f = min(1, max(0, fraction))
        let path = NSBezierPath()
        path.lineWidth = 1.7
        path.lineCapStyle = .round
        if f >= 0.999 {
            path.appendOval(in: NSRect(x: 1.5, y: 1.5, width: 19, height: 19))
        } else {
            path.appendArc(
                withCenter: NSPoint(x: 11, y: 11), radius: 9.5,
                startAngle: -90, endAngle: -90 + 360 * CGFloat(f), clockwise: false)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}
