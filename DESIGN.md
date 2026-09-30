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
- Radii: capsules for fields and buttons, 18 for grouped surfaces. The dock and tray use `ConcentricRectangle` on macOS 26+, so their corners follow the window's own corner radius (inset by their padding); earlier systems use a fixed 26.
- Title bar (`DownerWindowChrome`, `TitleBarRow`): no system title text. An empty unified toolbar gives the taller bar; the traffic lights, a centred semibold 13 pt title, and the trailing control all share one centre line 26 pt from the top, with a 20 pt inset on both sides. Content is laid out below the bar; only the title row reaches up into it. Main and Settings windows share this.

## Surfaces
- Main window 460×700: URL capsule, type selector, Video / Audio groups, Save to, Information, floating dock (Download, progress, status).
- Menu bar popover 360×180: system-drawn background, URL field with Paste, Download, status.
- Settings 400×560: Appearance (theme, glow), Global Shortcut, Requirements (yt-dlp, ffmpeg, ffprobe with Install).
- Download queue: links (single videos, playlists, or both) can be added at any time, one after another, by pasting into the field and pressing Return or "Add to Queue". They are looked up first (titles, playlist or not) and downloaded one at a time in order. Each job keeps the settings it was added with. Failed network downloads retry once on their own.
- Queue tray: shown when more than one link is queued or a playlist is downloading. The dock becomes a tray with a drag handle (peek 162, list 452, full 604 pt). Peek shows title, ring, overall bar and current item; pulled up shows every item with its state and Retry for failures. A lone single video keeps the dock.
- Menu bar icon (`MenuBarIcon.swift`): the app icon's double chevron as a template image; a progress ring while downloading (percentage, or item/total for playlists), a check for two seconds when done, an orange dot when a tool is missing or a run failed.
- App icon: layered `Downer.icon` (gradient plate, two glass chevron layers), Default / Dark / Clear / Tinted.

## Do not
Progress percentages (the app does not parse them), gradient text, extra glass on content rows, decorative blur.

## Implementation notes
- Motion: one language in `Motion` (smooth 0.3 s, quick 0.2 s, never bouncy). Every animation has a Reduce Motion path that keeps a brief fade.
- The progress bar is custom (`DownerProgressBar`) because the system linear style ignores the brand tint in dark mode.
- Tinted Liquid Glass renders grey inside an `NSPopover`, so the popover's Download button is solid red (`flat`).
