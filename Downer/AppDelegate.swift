//
// AppDelegate.swift
//  Downer
//
//  Created by Dumindu Sameendra on 2025-04-17.
//

import Cocoa
import KeyboardShortcuts
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    static private(set) var shared: AppDelegate!  // singleton

    var mainWindow: NSWindow!
    var statusItem: NSStatusItem!
    var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        let hostVC = NSHostingController(rootView: MainAppView())
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.contentViewController = hostVC
        w.title = "Downer"
        w.titleVisibility            = .visible
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.backgroundColor            = .black
        w.center()
        w.delegate = self
        w.makeKeyAndOrderFront(nil)
        w.isReleasedWhenClosed = false
        self.mainWindow = w
        

        // show dock icon
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // build the menu‑bar pop‑over
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 200)
        popover.contentViewController =
            NSHostingController(rootView: PopOverView())

        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        if let btn = statusItem.button {
            let cfg = NSImage.SymbolConfiguration(
                pointSize: 16,
                weight: .regular
            )
            btn.image = NSImage(
                systemSymbolName: "chevron.down.square.fill",
                accessibilityDescription: "Downer"
            )?
            .withSymbolConfiguration(cfg)
            btn.image?.isTemplate = true
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
            btn.action = #selector(statusItemClicked(_:))
            btn.target = self
        }

        // register global shortcut
        KeyboardShortcuts.onKeyDown(for: .downloadShortcut) { [weak self] in
            self?.togglePopover(nil)
        }
    }

    // context menu builder
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(
            NSMenuItem(
                title: "Open Downer",
                action: #selector(openFullApp),
                keyEquivalent: ""
            )
        )

        menu.addItem(.separator())

        menu.addItem(
            NSMenuItem(
                title: "Quit Downer",
                action: #selector(quitApp),
                keyEquivalent: "q"
            )
        )

        menu.items.forEach { $0.target = self }
        return menu
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === mainWindow else { return true }

        // hide the window rather than destroying it
        sender.orderOut(nil)

        // turn the app back into a menu‑bar
        NSApp.setActivationPolicy(.accessory)

        // disable normal close behaviour
        return false
    }

    // Click handler
    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        {
            statusItem.menu = buildMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover(sender)
        }
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

    //
    @objc func openFullApp() {
        // if the window vanished recreate it again
        if mainWindow == nil {
            let hostVC = NSHostingController(rootView: MainAppView())
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.contentViewController = hostVC
            w.title = "Downer"
            w.titleVisibility            = .visible
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.backgroundColor            = .black
            w.isReleasedWhenClosed = false
            w.delegate = self
            mainWindow = w
        }

        // reshow dock icon & app
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // bring window to the front
        mainWindow!.makeKeyAndOrderFront(nil)
    }
    
    // Quit handler
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
