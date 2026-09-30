//
// AppDelegate.swift
//  Downer
//
//  Created by Dumindu Sameendra on 2025-04-17.
//

import Cocoa
import Combine
import KeyboardShortcuts
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {

    static private(set) var shared: AppDelegate!  // singleton

    var mainWindow: NSWindow!
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        AppearanceMode.apply(
            UserDefaults.standard.string(forKey: AppearanceMode.storageKey) ?? "system")

        let hostVC = NSHostingController(rootView: MainAppView())
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.contentViewController = hostVC
        DownerWindowChrome.apply(to: w, title: "Downer")
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
        popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 180)
        popover.contentViewController =
            NSHostingController(rootView: PopOverView())

        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        if let btn = statusItem.button {
            btn.image = MenuBarIcon.image(for: .idle)
            btn.imagePosition = .imageLeading
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
            btn.action = #selector(statusItemClicked(_:))
            btn.target = self
        }

        // the icon follows the download: ring while running, check when done, dot when it needs you
        let dl = DownloadManager.shared
        let deps = DependencyManager.shared
        dl.objectWillChange
            .merge(with: deps.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
        dl.$completions
            .dropFirst()
            .sink { [weak self] _ in self?.flashDone() }
            .store(in: &cancellables)

        // register global shortcut
        KeyboardShortcuts.onKeyDown(for: .downloadShortcut) { [weak self] in
            self?.togglePopover(nil)
        }
    }

    // MARK: Menu bar icon
    private var showingDone = false
    private var lastIconState: MenuBarIcon.State?
    private var lastTitle = ""

    private func flashDone() {
        showingDone = true
        updateStatusItem()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            self?.showingDone = false
            self?.updateStatusItem()
        }
    }

    private func updateStatusItem() {
        guard let btn = statusItem.button else { return }
        let dl = DownloadManager.shared
        let deps = DependencyManager.shared

        let state: MenuBarIcon.State
        var title = ""
        if dl.isActive {
            state = .progress(dl.runningJob == nil ? nil : dl.progress)
            if let label = dl.queueLabel {
                title = " \(label)"
            } else if let progress = dl.progress, dl.runningJob != nil {
                title = " \(Int((progress * 100).rounded()))%"
            }
        } else if showingDone {
            state = .done
        } else if dl.hadError || (deps.hasCheckedOnce && !deps.missing.isEmpty) {
            state = .attention
        } else {
            state = .idle
        }

        // only touch the button when something changed; redrawing it on every output line is wasteful
        if state != lastIconState {
            lastIconState = state
            btn.image = MenuBarIcon.image(for: state)
        }
        if title != lastTitle {
            lastTitle = title
            btn.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)]
            )
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
            NSApp.activate(ignoringOtherApps: true)
            popover.show(
                relativeTo: btn.bounds,
                of: btn,
                preferredEdge: .minY
            )
            popover.contentViewController?.view.window?.becomeKey()
            NotificationCenter.default.post(name: .popoverWillShow, object: nil)
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
            DownerWindowChrome.apply(to: w, title: "Downer")
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
