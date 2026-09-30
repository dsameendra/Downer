# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

## Stack

Native macOS app (Impeccable has no macOS platform value; treat Apple HIG as the reference). Deployment target 14.0 / 15.4, Xcode 27. Existing native codebase: SwiftUI + AppKit, KeyboardShortcuts package. Liquid Glass must be adaptive: real `glassEffect` / `GlassEffectContainer` on macOS 26+, a refined material fallback on macOS 14-15 (confirmed by user).

## Users

People who download video or audio from YouTube and similar sites and want it without a terminal. Two equal situations (confirmed): a quick grab from the menu bar (copy link, shortcut, paste, go) and a deliberate session in the main window (tuning resolution, container, audio quality).

## Product Purpose

Downer is a lightweight native front end for yt-dlp and ffmpeg. Paste a link, choose video+audio, audio-only or video-only, pick resolution, container, audio quality and destination, press Download. While it runs, more links (single videos, playlists, or both) can be added; they queue and download in order. Success is a finished file in the chosen folder with as few decisions as possible.

## Positioning

Lives in the menu bar and a global shortcut, and shares one set of remembered defaults between the popover and the main window. Not a browser extension, not a CLI.

## Operating Context

- Main window is 460 pt wide with a fixed 640 pt of content below a taller, toolbar-height title bar; closing it hides it and the Dock icon.
- Menu bar popover is 360x180 and shares settings and the queue with the main window. The global shortcut opens it and fills in a copied link.
- Settings window (400 wide): appearance (theme, background glow), global shortcut, and requirements (yt-dlp, ffmpeg, ffprobe) with install.
- Status is a single line (Idle, Checking link…, Downloading 42% · speed · time left, completed, errors). Real progress is parsed from yt-dlp output: per video, per playlist and across the whole queue.

## Capabilities and Constraints

- Download types: Video + Audio, Audio only, Video only.
- A queue: any number of links, added at any time, run one at a time in order. Each link keeps the settings it had when added. Playlists expand into one row per video with retry for failures. Network errors retry once automatically.
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
5. Adding is never blocked: the next link can always be pasted, whatever is running.

## Accessibility & Inclusion

Honor Reduce Transparency, Increase Contrast, Reduce Motion; keep text contrast readable over glass in light and dark.
