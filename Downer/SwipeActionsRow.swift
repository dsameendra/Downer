//
//  SwipeActionsRow.swift
//  Downer
//
//  A queue row that slides open under two fingers to show what you can do with it. The row
//  follows your fingers 1:1, ticks when a full swipe would trigger the main action, and lets go
//  with the speed of your swipe. Every action is also in the right-click menu and in VoiceOver's
//  actions list, so nothing depends on a trackpad.
//

import SwiftUI

struct SwipeAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: Color
    let handler: () -> Void
}

/// `actions` read left to right; the last one is what a full swipe triggers.
struct SwipeActionsRow<Content: View>: View {
    let actions: [SwipeAction]
    let isOpen: Bool
    let onOpenChange: (Bool) -> Void
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0  // 0 closed, negative open
    @State private var rowWidth: CGFloat = 0
    @State private var model = SwipeReveal(actionWidth: 1, rowWidth: 1)
    @State private var driver = SpringDriver()
    @State private var panning = false
    @State private var committing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let chip: CGFloat = 58
    private let spacing: CGFloat = 6
    private let edge: CGFloat = 4

    private var restWidth: CGFloat {
        SwipeActionLayout.restingWidth(count: actions.count, chip: chip, spacing: spacing) + edge * 2
    }
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    var body: some View {
        content()
            .offset(x: offset)
            .overlay {
                if offset < -1 && !panning {
                    Color.clear.contentShape(Rectangle()).onTapGesture { close() }
                }
            }
            .overlay(alignment: .trailing) { actionStrip }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { rowWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, width in rowWidth = width }
                }
            )
            .background(TrackpadScrollRegion(handlers: scrollHandlers))
            .contextMenu {
                ForEach(actions) { action in
                    Button(action.title, systemImage: action.systemImage, action: action.handler)
                }
            }
            .modifier(AccessibilityActions(actions: actions))
            .onAppear {
                driver.onUpdate = { offset = $0 }
            }
            .onChange(of: isOpen) { _, open in
                if !open, !panning, !committing, offset < -0.5 { animate(to: 0, velocity: 0) }
            }
    }

    // MARK: Revealed buttons
    private var actionStrip: some View {
        let revealed = max(0, -offset)
        let widths = SwipeActionLayout.widths(
            count: actions.count, revealed: max(0, revealed - edge * 2), chip: chip, spacing: spacing)
        return HStack(spacing: spacing) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                VStack(spacing: 2) {
                    Image(systemName: action.systemImage).font(.system(size: 14, weight: .semibold))
                    Text(action.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(.white)
                .frame(width: widths[index], height: 40)
                .background(action.tint.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture {
                    close()
                    action.handler()
                }
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, edge)
        .frame(width: revealed, alignment: .trailing)
        .clipped()
        .opacity(min(1, revealed / 24))
        .allowsHitTesting(revealed > 8)
    }

    // MARK: Gesture
    private var scrollHandlers: TrackpadScrollHandlers {
        var h = TrackpadScrollHandlers()
        h.decide = { intent in
            guard intent.axis == .horizontal, !committing else { return false }
            return intent.right < 0 || offset < -0.5
        }
        h.began = {
            if driver.isRunning { offset = driver.stop() }
            model = SwipeReveal(actionWidth: restWidth, rowWidth: max(rowWidth, restWidth * 2))
            model.begin(at: offset, time: now)  // from wherever the row is right now
            panning = true
            onOpenChange(true)
        }
        h.changed = { right, _, time in
            if model.move(by: right, at: time) { Haptics.tick() }
            offset = model.offset
        }
        h.ended = { time in
            panning = false
            let result = model.end(at: time)
            switch result.outcome {
            case .commit:
                Haptics.notch()
                commit()
            case .open:
                animate(to: -restWidth, velocity: result.settle.velocity)
            case .close:
                animate(to: 0, velocity: result.settle.velocity)
                onOpenChange(false)
            }
        }
        return h
    }

    private func commit() {
        guard let primary = actions.last else { return close() }
        committing = true
        driver.onFinish = {
            driver.onFinish = {}
            primary.handler()
            committing = false
            onOpenChange(false)
            withAnimation(Motion.standard(reduce: reduceMotion)) { offset = 0 }
        }
        animate(to: -max(rowWidth, restWidth), velocity: 0)
    }

    private func close() {
        onOpenChange(false)
        animate(to: 0, velocity: 0)
    }

    private func animate(to target: CGFloat, velocity: CGFloat) {
        if reduceMotion {
            driver.stop()
            withAnimation(Motion.reduced) { offset = target }
        } else {
            driver.animate(from: offset, to: target, velocity: velocity)
        }
    }
}

/// VoiceOver lists each action on the row.
private struct AccessibilityActions: ViewModifier {
    let actions: [SwipeAction]

    func body(content: Content) -> some View {
        actions.reduce(AnyView(content)) { view, action in
            AnyView(view.accessibilityAction(named: Text(action.title), action.handler))
        }
    }
}
