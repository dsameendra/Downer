//
// AppDelegate.swift
//  Downer
//
//  Created by Dumindu Sameendra on 2025-04-17.
//

import Cocoa
import SwiftUI
import KeyboardShortcuts

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    static private(set) var shared: AppDelegate! // Singleton

    var mainWindow: NSWindow!
    var statusItem: NSStatusItem!
    var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // 1) Build your full‑app window and store it
        let hostVC = NSHostingController(rootView: MainDownloadView())
        let w = NSWindow(
          contentRect: NSRect(x: 0, y: 0, width: 400, height: 540),
          styleMask: [.titled, .closable, .miniaturizable, .resizable],
          backing: .buffered,
          defer: false
        )
        w.contentViewController = hostVC
        w.title                = "Downer"
        w.center()
        w.delegate             = self
        w.makeKeyAndOrderFront(nil)
        w.isReleasedWhenClosed = false
        self.mainWindow        = w

        // show Dock icon
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // 3) Build the menu‑bar pop‑over
        popover = NSPopover()
        popover.behavior            = .transient
        popover.contentSize         = NSSize(width: 360, height: 200)
        popover.contentViewController =
            NSHostingController(rootView: MiniDownloadView())

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
               if let btn = statusItem.button {
                   btn.image  = NSImage(systemSymbolName: "arrow.down.circle.fill",
                                        accessibilityDescription: "Downer")

                   btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
                   btn.action = #selector(statusItemClicked(_:))
                   btn.target = self
               }


        // 4) Register global shortcut
        KeyboardShortcuts.onKeyDown(for: .downloadShortcut) { [weak self] in
            self?.togglePopover(nil)
        }
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === mainWindow else { return true }

        // 1) Hide the window rather than destroying it
        sender.orderOut(nil)

        // 2) Turn the app back into a menu‑bar extra
        NSApp.setActivationPolicy(.accessory)

        // 3) Don’t let Cocoa continue with the normal close behaviour
        return false
    }
    
    // Click handler
    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            // RIGHT click  → show menu
            statusItem.menu = buildMenu()
            statusItem.button?.performClick(nil)   // show menu now
            statusItem.menu = nil                  // detach afterwards to keep left‑click pop‑over working
        } else {
            // LEFT click   → toggle pop‑over
            togglePopover(sender)
        }
    }
    
    // Context menu builder
        private func buildMenu() -> NSMenu {
            let menu = NSMenu()

            menu.addItem(NSMenuItem(
                title: "Open Downer",
                action: #selector(openFullApp),
                keyEquivalent: ""))

            menu.addItem(.separator())

            menu.addItem(NSMenuItem(
                title: "Quit Downer",
                action: #selector(quitApp),
                keyEquivalent: "q"))

            // Make sure items send actions to us
            menu.items.forEach { $0.target = self }
            return menu
        }

        // Quit handler
        @objc private func quitApp() {
            NSApp.terminate(nil)
        }


    // MARK: Popover
    @objc func togglePopover(_ sender: Any?) {
        guard let btn = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(
              relativeTo: btn.bounds,
              of: btn,
              preferredEdge: .minY
            )
            popover.contentViewController?.view.window?.becomeKey()
        }
    }

    @objc func openFullApp() {
        // If, for some reason, the window vanished, recreate it
        if mainWindow == nil {
            let hostVC = NSHostingController(rootView: MainDownloadView())
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.contentViewController = hostVC
            w.title = "Downer"
            w.isReleasedWhenClosed = false
            w.delegate = self
            mainWindow = w
        }

        // Show Dock icon & app menu again
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Bring the window to the front
        mainWindow!.makeKeyAndOrderFront(nil)
    }
}
