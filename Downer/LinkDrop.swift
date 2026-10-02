//
//  LinkDrop.swift
//  Downer
//
//  Drop a link on the window, or on the menu bar icon, and it joins the queue. A glowing edge
//  shows the window is listening, and a tick confirms the drop.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Accepts links dragged from a browser (as a URL or as text). `perform` gets the text to add.
    func linkDrop(perform: @escaping (String) -> Void) -> some View {
        modifier(LinkDropTarget(perform: perform))
    }
}

private struct LinkDropTarget: ViewModifier {
    let perform: (String) -> Void
    @State private var targeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.url, .plainText], isTargeted: $targeted) { providers in
                LinkDropReader.read(providers) { text in
                    Haptics.notch()
                    perform(text)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Brand.red.opacity(0.85), lineWidth: 2.5)
                    .shadow(color: Brand.red.opacity(0.6), radius: 10)
                    .padding(6)
                    .opacity(targeted ? 1 : 0)
                    .allowsHitTesting(false)
                    .animation(Motion.quick, value: targeted)
            }
            .onChange(of: targeted) { _, inside in if inside { Haptics.tick() } }
            .accessibilityAction(named: Text("Add link from clipboard")) {
                if let text = NSPasteboard.general.string(forType: .string) { perform(text) }
            }
    }
}

enum LinkDropReader {
    /// Reads a URL or text out of whatever was dropped, then calls `done` on the main actor.
    /// Returns whether anything readable was offered.
    static func read(_ providers: [NSItemProvider], done: @escaping @MainActor (String) -> Void) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, !url.isFileURL else { return }
                    Task { @MainActor in done(url.absoluteString) }
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                accepted = true
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let text else { return }
                    Task { @MainActor in done(text) }
                }
            }
        }
        return accepted
    }
}

/// Sits over the menu bar icon and accepts links dropped on it. Clicks pass straight through.
final class StatusItemDropView: NSView {
    var onDrop: (String) -> Void = { _ in }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.URL, .string])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Only drags may land here; mouse clicks go to the button underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        switch NSApp.currentEvent?.type {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: return super.hitTest(point)
        default: return nil
        }
    }

    private func text(from pasteboard: NSPasteboard) -> String? {
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first, !url.isFileURL {
            return url.absoluteString
        }
        return pasteboard.string(forType: .string)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let text = text(from: sender.draggingPasteboard), !DownloadManager.links(in: text).isEmpty else { return [] }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let text = text(from: sender.draggingPasteboard) else { return false }
        Haptics.notch()
        onDrop(text)
        return true
    }
}
