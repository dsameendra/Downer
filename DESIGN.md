# Design

Liquid Glass redesign of Downer, approved from the "Downer Liquid Glass" design canvas.

## Principles
- Glass is the control layer only: URL field, type selector, toolbar button, bottom dock, Download button. Content (option rows, Save to, Information, Settings groups) sits on flat surfaces, so glass never sits on glass.
- Real Liquid Glass (`glassEffect`, `GlassEffectContainer`) on macOS 26+. `.ultraThinMaterial` fallback on macOS 14–15. Opaque system colours when Reduce Transparency is on.
- Red is the identity and is reserved for the primary action, the progress line, and the switch. Everything else is neutral.
- Native first: system menus, segmented picker, switch, SF Symbols, system text sizes (13 body, 12 caption, 15–16 action).

## Tokens (see `Downer/DesignSystem.swift`)
- `Brand.red` #F0384A, `Brand.redLight` #FF5468, `Brand.redDeep` #D9213C.
- Window ground: `AmbientBackground`. Glow on: ink (#0E0A0C) or porcelain (#F8F3F4) with three soft radial colour fields (ember red, violet or periwinkle, rose or peach). Glow off: `windowBackgroundColor`. Setting: `backgroundGlow`, default on.
- Appearance: `appearanceMode` = system | light | dark, applied to `NSApp.appearance`.
- Radii: capsules for fields and buttons, 18 for grouped surfaces, 34 for the dock.

## Surfaces
- Main window 460×700: URL capsule, type selector, Video / Audio groups, Save to, Information, floating dock (Download, progress, status).
- Menu bar popover 360×180: system-drawn background, URL field with Paste, Download, status.
- Settings 400×560: Appearance (theme, glow), Global Shortcut, Requirements (yt-dlp, ffmpeg, ffprobe with Install).
- App icon: layered `Downer.icon` (gradient plate, two glass chevron layers), Default / Dark / Clear / Tinted.

## Do not
Progress percentages (the app does not parse them), gradient text, extra glass on content rows, decorative blur.
