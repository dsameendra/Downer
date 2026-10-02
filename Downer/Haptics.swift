//
//  Haptics.swift
//  Downer
//
//  Subtle trackpad feedback for snaps, thresholds and completions. A no-op on
//  trackpads without haptics, and switched off by Settings → Haptic feedback.
//

import AppKit

@MainActor
enum Haptics {
    static let storageKey = "hapticsEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true
    }

    /// A light tick: a snap, a slot change while reordering, a swipe threshold.
    static func tick() { perform(.alignment) }

    /// A firmer notch: something finished.
    static func notch() { perform(.levelChange) }

    private static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard isEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
