//
//  GlassSegmentedControl.swift
//  Downer
//
//  A glass segmented control whose thumb follows your fingers. Click a segment, drag the thumb
//  with a mouse, or swipe sideways with two fingers on a trackpad: the thumb tracks 1:1, resists
//  at the ends, and settles on the nearest segment carrying the speed of your swipe.
//

import SwiftUI

struct GlassSegmentedControl<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
    }

    let options: [Option]
    @Binding var selection: Value
    var height: CGFloat = 42
    var fontSize: CGFloat = 13
    var label: String

    @State private var position: CGFloat = 0  // in segments: 0 is the first
    @State private var trackWidth: CGFloat = 0
    @State private var pan = SnapPan(points: [0])
    @State private var driver = SpringDriver()
    @State private var panning = false
    @State private var lastTranslation: CGFloat?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let inset: CGFloat = 3
    private var selectedIndex: Int { options.firstIndex { $0.value == selection } ?? 0 }
    private var segmentWidth: CGFloat { max(1, (trackWidth - inset * 2) / CGFloat(max(options.count, 1))) }
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    var body: some View {
        ZStack(alignment: .leading) {
            thumb
            HStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    let closeness = max(0, 1 - abs(position - CGFloat(index)))
                    Text(option.title)
                        .font(.system(size: fontSize, weight: closeness > 0.5 ? .semibold : .medium))
                        .foregroundStyle(Color.primary.opacity(0.62 + 0.38 * closeness))
                        .frame(maxWidth: .infinity)
                        .frame(height: height - inset * 2)
                        .contentShape(Rectangle())
                        .onTapGesture { choose(index) }
                }
            }
        }
        .padding(inset)
        .frame(height: height)
        .downerGlass(in: Capsule())
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { trackWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in trackWidth = width }
            }
        )
        .background(TrackpadScrollRegion(handlers: scrollHandlers))
        .gesture(dragGesture)
        .onAppear {
            position = CGFloat(selectedIndex)
            driver.onUpdate = { position = $0 }
        }
        .onChange(of: selection) { _, _ in
            // changed from outside (not by us): glide to it
            if !panning, !driver.isRunning, abs(position - CGFloat(selectedIndex)) > 0.01 {
                animate(to: CGFloat(selectedIndex), velocity: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(options.indices.contains(selectedIndex) ? options[selectedIndex].title : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: choose(min(selectedIndex + 1, options.count - 1))
            case .decrement: choose(max(selectedIndex - 1, 0))
            @unknown default: break
            }
        }
    }

    private var thumb: some View {
        Capsule()
            .fill(colorScheme == .dark ? Color.white.opacity(0.20) : Color.white)
            .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
            .frame(width: segmentWidth, height: height - inset * 2)
            .offset(x: position * segmentWidth)
    }

    // MARK: Interaction
    private var scrollHandlers: TrackpadScrollHandlers {
        var h = TrackpadScrollHandlers()
        h.decide = { intent in intent.axis == .horizontal }
        h.began = { beginPan() }
        h.changed = { right, _, time in movePan(by: right, at: time) }
        h.ended = { time in endPan(at: time) }
        return h
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if lastTranslation == nil {
                    beginPan()
                    lastTranslation = 0
                }
                let delta = value.translation.width - (lastTranslation ?? 0)
                lastTranslation = value.translation.width
                movePan(by: delta, at: now)
            }
            .onEnded { _ in
                lastTranslation = nil
                endPan(at: now)
            }
    }

    private func beginPan() {
        if driver.isRunning { position = driver.stop() }
        pan = SnapPan(
            points: options.indices.map { CGFloat($0) }, rubberRange: 0.35,
            decelerationRate: Motion.deceleration)
        pan.begin(at: position, time: now)
        panning = true
    }

    private func movePan(by points: CGFloat, at time: TimeInterval) {
        pan.move(by: points / segmentWidth, at: time)
        position = pan.value
    }

    private func endPan(at time: TimeInterval) {
        let settle = pan.settle(at: time)
        panning = false
        animate(to: settle.target, velocity: settle.velocity)
        commit(Int(settle.target.rounded()))
    }

    private func choose(_ index: Int) {
        guard options.indices.contains(index) else { return }
        animate(to: CGFloat(index), velocity: 0)
        commit(index)
    }

    private func commit(_ index: Int) {
        guard options.indices.contains(index), options[index].value != selection else { return }
        withAnimation(Motion.standard(reduce: reduceMotion)) { selection = options[index].value }
        Haptics.tick()
    }

    private func animate(to target: CGFloat, velocity: CGFloat) {
        if reduceMotion {
            driver.stop()
            withAnimation(Motion.reduced) { position = target }
        } else {
            driver.animate(from: position, to: target, velocity: velocity)
        }
    }
}
