# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

## Stack

Native macOS app (Impeccable has no macOS platform value; treat Apple HIG as the reference). Deployment target 14.0 / 15.4, Xcode 27. Existing native codebase: SwiftUI + AppKit, KeyboardShortcuts package. Liquid Glass must be adaptive: real `glassEffect` / `GlassEffectContainer` on macOS 26+, a refined material fallback on macOS 14-15 (confirmed by user).

## Users

People who download video or audio from YouTube and similar sites and want it without a terminal. Two equal situations (confirmed): a quick grab from the menu bar (copy link, shortcut, paste, go) and a deliberate session in the main window (tuning resolution, container, audio quality).

## Product Purpose

Downer is a lightweight native front end for yt-dlp and ffmpeg. Paste a URL, choose video+audio, audio-only or video-only, pick resolution, container, audio quality and destination, press Download. Success is a finished file in the chosen folder with as few decisions as possible.

## Positioning

Lives in the menu bar and a global shortcut, and shares one set of remembered defaults between the popover and the main window. Not a browser extension, not a CLI.

## Operating Context

- Main window is fixed at 460x700; closing it hides it and the Dock icon.
- Menu bar popover is 360x180 and shares settings with the main window.
- Settings window (400x300): global shortcut and tool paths (yt-dlp, ffmpeg, ffprobe, default /opt/homebrew/bin).
- Status is a single text line (Idle, Starting download..., completed, path errors). No numeric progress is currently surfaced.

## Capabilities and Constraints

- Download types: Video + Audio, Audio only, Video only.
- Video: resolution, container. Audio: quality (source, up to N kbps), format (source, MP3, AAC/M4A, Opus).
- Persistent defaults via AppStorage; all existing behavior and copy stay.
- Dark and light mode both required.

## Brand Commitments

Name "Downer". Red accent is the current identity (red gradient buttons, `.tint(.red)`). The brief asks for a Liquid Glass, more modern and sleek redesign, so the red accent may be re-tuned but should stay recognizably Downer unless the user says otherwise.

## Evidence on Hand

README screenshots (imgur links) of dark, light, menubar and settings. App icon set in Assets.xcassets. No testimonials or metrics; do not invent any.

## Product Principles

1. The URL field and Download button are the whole job; everything else is a default you set once.
2. Popover and main window are one product, one visual language.
3. Native first: system controls, system materials, respect Reduce Transparency and Increase Contrast.
4. Status should feel alive without lying: show only what yt-dlp actually reports.

## Accessibility & Inclusion

Honor Reduce Transparency, Increase Contrast, Reduce Motion; keep text contrast readable over glass in light and dark.
