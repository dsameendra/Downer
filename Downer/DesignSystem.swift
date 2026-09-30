//
//  DesignSystem.swift
//  Downer
//
//  Liquid Glass tokens and shared components. Real glass on macOS 26+,
//  a material fallback on macOS 14–15, opaque surfaces when the user
//  turns on Reduce Transparency.
//

import AppKit
import SwiftUI

// MARK: - Brand

enum Brand {
    static let red = Color(red: 0.94, green: 0.22, blue: 0.29)
    static let redLight = Color(red: 1.0, green: 0.33, blue: 0.41)
    static let redDeep = Color(red: 0.85, green: 0.13, blue: 0.24)

    static var redGradient: LinearGradient {
        LinearGradient(
            colors: [redLight, redDeep],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Glass

/// Glass for the control layer: fields, selectors, docks, toolbar buttons.
/// Content sections use `.downerSurface()` instead, so glass never sits on glass.
private struct DownerGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color?
    var interactive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(nsColor: .controlBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.16), lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }
}

/// Content layer: grouped rows that sit on the window ground, not on glass.
private struct DownerSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private var fill: Color {
        if reduceTransparency {
            return Color(nsColor: .controlBackgroundColor)
        }
        return colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.58)
    }
}

extension View {
    func downerGlass<S: InsettableShape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(DownerGlass(shape: shape, tint: tint, interactive: interactive))
    }

    func downerSurface(cornerRadius: CGFloat = 18) -> some View {
        modifier(DownerSurface(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }
}

/// Groups neighbouring glass so it can blend and morph on macOS 26+.
struct DownerGlassGroup<Content: View>: View {
    var spacing: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

// MARK: - Ambient background

/// Window ground. With the glow on it paints soft colour for the glass to
/// refract; with it off (or Reduce Transparency on) it is the plain system window.
/// The glow fades in and out rather than cutting.
struct AmbientBackground: View {
    @AppStorage("backgroundGlow") private var glow = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            glowLayer
                .opacity(glow && !reduceTransparency ? 1 : 0)
        }
        .motion(.smooth(duration: 0.6), value: glow)
        .ignoresSafeArea()
    }

    private var glowLayer: some View {
        ZStack {
            colorScheme == .dark
                ? Color(red: 0.055, green: 0.04, blue: 0.05)
                : Color(red: 0.97, green: 0.95, blue: 0.96)
            blob(colors.top, at: UnitPoint(x: 0.78, y: -0.06), radius: 380)
            blob(colors.side, at: UnitPoint(x: 0.0, y: 0.46), radius: 360)
            blob(colors.bottom, at: UnitPoint(x: 0.88, y: 0.96), radius: 420)
        }
    }

    private var colors: (top: Color, side: Color, bottom: Color) {
        colorScheme == .dark
            ? (
                Color(red: 0.94, green: 0.22, blue: 0.29).opacity(0.62),
                Color(red: 0.34, green: 0.23, blue: 0.75).opacity(0.42),
                Color(red: 0.84, green: 0.16, blue: 0.34).opacity(0.46)
            )
            : (
                Color(red: 1.0, green: 0.43, blue: 0.49).opacity(0.55),
                Color(red: 0.55, green: 0.63, blue: 1.0).opacity(0.40),
                Color(red: 1.0, green: 0.71, blue: 0.51).opacity(0.50)
            )
    }

    private func blob(_ color: Color, at center: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(
            colors: [color, .clear],
            center: center,
            startRadius: 0,
            endRadius: radius
        )
    }
}

// MARK: - Controls

/// The one red control. Tinted glass on macOS 26+, flat red gradient before that.
/// `isCancel` swaps it for clear glass while a download is running.
struct DownloadButtonStyle: ButtonStyle {
    var isCancel = false
    var height: CGFloat = 52
    /// Solid red instead of tinted glass, for surfaces that already are a system
    /// material (the menu bar popover renders tinted glass grey).
    var flat = false

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: height > 48 ? 16 : 15, weight: .semibold))
            .foregroundStyle(isCancel ? Color.primary : Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .modifier(ActionSurface(isCancel: isCancel, flat: flat, reduceTransparency: reduceTransparency))
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private struct ActionSurface: ViewModifier {
        let isCancel: Bool
        let flat: Bool
        let reduceTransparency: Bool

        func body(content: Content) -> some View {
            if isCancel {
                content.downerGlass(in: Capsule(), interactive: true)
            } else if reduceTransparency {
                content.background(Brand.redDeep, in: Capsule())
            } else if !flat, #available(macOS 26.0, *) {
                content.glassEffect(.regular.tint(Brand.red).interactive(), in: Capsule())
            } else {
                content
                    .background(Brand.redGradient, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
                    .shadow(color: Brand.red.opacity(0.4), radius: 10, x: 0, y: 5)
            }
        }
    }
}

/// Small capsule button used for Change, Browse…, Paste.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration)
    }

    private struct PillBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    Color.primary.opacity(configuration.isPressed ? 0.20 : hovering ? 0.15 : 0.10),
                    in: Capsule()
                )
                .onHover { hovering = $0 }
                .motion(Motion.quick, value: hovering)
                .motion(Motion.quick, value: configuration.isPressed)
        }
    }
}

/// Red capsule for the one obvious next step inside a row (Install).
struct PrimaryPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryBody(configuration: configuration)
    }

    private struct PrimaryBody: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(
                    (hovering ? Brand.red : Brand.redDeep).opacity(configuration.isPressed ? 0.8 : 1),
                    in: Capsule()
                )
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovering = $0 }
                .motion(Motion.quick, value: hovering)
        }
    }
}

/// Circular glass toolbar button.
struct GlassCircleButtonStyle: ButtonStyle {
    var size: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        CircleBody(configuration: configuration, size: size)
    }

    private struct CircleBody: View {
        let configuration: Configuration
        let size: CGFloat
        @State private var hovering = false

        var body: some View {
            configuration.label
                .frame(width: size, height: size)
                .downerGlass(in: Circle(), interactive: true)
                .scaleEffect(configuration.isPressed ? 0.94 : hovering ? 1.06 : 1)
                .onHover { hovering = $0 }
                .motion(Motion.quick, value: hovering)
                .motion(Motion.quick, value: configuration.isPressed)
        }
    }
}

/// Status icon + text shared by the window and the popover. The icon becomes a
/// check (with one bounce) when a download completes, and pulses while one runs.
struct DownloadStatusLine: View {
    let status: String
    let isDownloading: Bool
    var completions = 0

    private var completed: Bool { status.contains("completed") }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: completed ? "checkmark.circle.fill" : "circle.fill")
                .font(.system(size: completed ? 13 : 7, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: completions)
                .symbolEffect(.pulse, isActive: isDownloading)
                .frame(width: 14, height: 14)
            Text(status)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
        .motion(Motion.quick, value: status)
    }

    private var tint: Color {
        if isDownloading { return .orange }
        return status == "Idle" || completed ? .green : .orange
    }
}

// MARK: - Motion

/// One motion language: short, decelerating, never bouncy. Every helper honours
/// Reduce Motion by dropping movement and keeping a brief fade.
enum Motion {
    static let standard = Animation.smooth(duration: 0.3)
    static let quick = Animation.snappy(duration: 0.2)
    static let enter = Animation.smooth(duration: 0.45)
    static let reduced = Animation.easeInOut(duration: 0.12)

    static func standard(reduce: Bool) -> Animation { reduce ? reduced : standard }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? Motion.reduced : animation, value: value)
    }
}

private struct AppearModifier: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear {
                withAnimation(
                    (reduceMotion ? Motion.reduced : Motion.enter)
                        .delay(reduceMotion ? 0 : Double(index) * 0.04)
                ) { shown = true }
            }
    }
}

extension View {
    /// Animates changes of `value` with the app's motion language.
    func motion<V: Equatable>(_ animation: Animation = Motion.standard, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }

    /// Short staggered entrance for a group of sections (40 ms apart, 8 pt rise).
    func appear(_ index: Int) -> some View {
        modifier(AppearModifier(index: index))
    }
}

// MARK: - Appearance

/// User-chosen appearance. `system` follows the device.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearanceMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Device"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// Applies to every window and the menu bar popover.
    static func apply(_ raw: String) {
        NSApp.appearance = (AppearanceMode(rawValue: raw) ?? .system).nsAppearance
    }
}
