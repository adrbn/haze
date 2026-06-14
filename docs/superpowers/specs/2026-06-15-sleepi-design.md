# Sleepi — Design Spec

_Date: 2026-06-15 · Status: approved (full-autonomy one-shot build)_

## Goal

A lightweight, native macOS app that drives three surfaces from **one shared
render core**:

1. **Live desktop wallpaper** — animated video / GIF / Metal gradient as the
   desktop background (the Wallper-style core feature).
2. **Screensaver** — the same content shown when the Mac is idle (the closest
   real thing to "the screen while it's resting"; macOS has no renderable
   surface during true sleep).
3. **Metal gradient generator** — flowing, shadergradient.co-inspired gradients
   usable as both wallpaper and screensaver.

Native **Liquid Glass** UI (macOS 26) with `.ultraThinMaterial` fallback on
macOS 15. Non-sandboxed, notarizable, **GPL-3.0**, free and open source.

## Decisions

| Topic | Decision |
|---|---|
| Min macOS | 15.0 (Sequoia); Liquid Glass on 26 via availability checks |
| Language | Swift, **Swift 5 language mode** on the Swift 6.2 compiler (stability) |
| Project | XcodeGen `project.yml` (reproducible, reviewable); build via `xcodebuild` |
| Process model | Single `LSUIElement` menu-bar agent renders wallpaper + hosts UI |
| Sharing | `~/Library/Application Support/Sleepi/` shared dir (no App Group — non-sandboxed) |
| Library store | JSON manifest + media files on disk (inspectable, community-friendly) |
| Distribution | Non-sandboxed, ad-hoc-signable locally, notarize for release. Not App Store. |
| License | GPL-3.0 |

## Targets

- **SleepiKit** (framework) — model, library, renderers, gradient shaders,
  playback/power policy, display management. Shared by app + screensaver.
- **Sleepi** (app, menu-bar agent) — Liquid-glass UI + wallpaper renderer host.
- **SleepiSaver** (`.saver` bundle) — screensaver reusing SleepiKit renderers.
- **SleepiKitTests** — unit tests on the logic-heavy core (target ≥80%).

## Render core

`WallpaperRenderer` protocol vends an `NSView` and supports
`start/pause/resume/stop`. Concrete renderers:

- `VideoRenderer` — `AVQueuePlayer` + `AVPlayerLooper` on `AVPlayerLayer`,
  hardware decode, seamless loop, audio stripped.
- `AnimatedImageRenderer` — GIF/APNG via ImageIO + `CAKeyframeAnimation`.
- `GradientRenderer` — `MTKView` + MSL fragment shader (domain-warped fbm noise,
  configurable palette/speed/grain).
- `StaticImageRenderer` — stills.

`DisplayManager` creates one desktop-level borderless `NSWindow` per `NSScreen`
(`desktopWindow` level, joins all Spaces, ignores mouse, behind icons), one
renderer per screen. **Slice 1: same content on all displays.** Per-display
content is the future dual-screen slice (architecture already supports it).

## Resource discipline

`PlaybackPolicy` (pure, testable) maps inputs → render/pause. `PowerMonitor`
feeds it:

- **Occlusion pause** (biggest lever): stop decoding when the desktop is fully
  covered.
- Pause on display sleep / system sleep / screen lock; resume on wake.
- Optional pause / FPS drop on battery + Low Power Mode.
- Adaptive FPS (cap to refresh; lower default for gradients).

Targets: ~0% CPU when occluded; low single-digit CPU for 1080p HEVC on Apple
Silicon.

## Data

- `ContentItem` (Codable): id, type, file URL, thumbnail, name/author/tags,
  per-item settings.
- `LibraryManager` imports media into the shared dir, generates thumbnails,
  persists a JSON `LibraryManifest`.
- `AppSettings` holds wallpaper + screensaver selections and preferences, also
  in the shared dir so `SleepiSaver` can read the current screensaver choice.
- Bundled shadergradient-inspired `GradientPreset`s + an in-app editor.

## UI (SwiftUI)

- `MenuBarExtra`: switch wallpaper, pause/resume, open library, quit.
- Main window: glass sidebar (Wallpapers / Gradients / Screensaver / Settings),
  rounded edgeless thumbnail grid with hover preview, gradient editor with live
  Metal preview, screensaver tab (install/update `.saver` + deep-link to System
  Settings), settings (battery behavior, FPS, launch-at-login).

## Out of scope (architected for, later slices)

- Login-window background (static, admin-only, OS-restricted) — `LoginScreenManager` stub.
- Per-display independent content (dual screen).
- Community catalogue sourcing/management.

## Testing

Unit tests: `LibraryManager` import/manifest round-trip, `PlaybackPolicy` state
machine, `GradientConfig`/preset Codable, content-type detection,
`ContentStore` paths. Rendering/screensaver activation → manual checklist
(needs GUI). Build bar: `xcodebuild` compiles all targets; tests pass.
