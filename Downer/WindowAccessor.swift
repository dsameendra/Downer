//
//  WindowAccessor.swift
//  Downer
//
//  Created by Dumindu Sameendra on 2025-04-24.
//

import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let style: (NSWindow) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(style: style)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                context.coordinator.register(window: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class Coordinator: NSObject {
        let style: (NSWindow) -> Void

        init(style: @escaping (NSWindow) -> Void) {
            self.style = style
        }

        func register(window: NSWindow) {
            // ensure full-size content view and non-opaque
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            style(window)

            // re-apply on move (keeps transparency when dragging)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidMove(_:)),
                name: NSWindow.didMoveNotification,
                object: window
            )
        }

        @objc func windowDidMove(_ note: Notification) {
            guard let window = note.object as? NSWindow else { return }
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            style(window)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
