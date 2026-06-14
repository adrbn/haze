<div align="center">

# 🌙 Sleepi

**Live wallpapers, an idle screensaver, and Metal gradients for macOS — native, lightweight, and free.**

Round, edgeless, Liquid‑Glass UI · sips resources · GPL‑3.0

</div>

---

Sleepi turns videos, GIFs, images, and animated **Metal gradients** (inspired by
[shadergradient.co](https://shadergradient.co)) into your **live desktop
wallpaper** and your **idle screensaver** — driven by one shared rendering core,
with aggressive power management so it stays out of the way.

> **A note on "the screen while sleeping":** when a Mac is *truly asleep* the
> display is off, so there is nothing to render. Sleepi covers the two surfaces
> that actually exist: the **live wallpaper** (and the lock screen, which macOS
> derives from it as a blur) and the **screensaver** shown while the Mac is idle.
> A static **login‑window background** is on the roadmap (it's admin‑only and
> OS‑restricted).

## Features

- 🎞 **Live wallpapers** — looping video (H.264/HEVC, hardware‑decoded), GIF/APNG, and stills.
- 🌈 **Gradient generator** — animated Metal gradients with editable palette, speed, warp, grain, and three styles (Aurora / Liquid / Halo). Eight presets bundled.
- 💤 **Screensaver** — a real `.saver` plugin that reuses the same renderers and your chosen content.
- 🪶 **Lightweight by design** — pauses rendering when the desktop is fully covered, the display sleeps, the screen locks, or (optionally) on battery / Low Power Mode. ~0% CPU when occluded.
- 🧊 **Native Liquid Glass UI** — real Liquid Glass on macOS 26, graceful `.ultraThinMaterial` fallback on 15.
- 🍎 **Menu‑bar agent** — no Dock clutter; quick switch / pause from the menu bar.
- 🖥 **Multi‑display** — every screen gets the wallpaper today; independent per‑display content is on the roadmap.

## Requirements

- macOS **15.0+** (built and tested on macOS 26)
- Xcode **26** with the **Metal Toolchain** component
- [XcodeGen](https://github.com/yonyz/XcodeGen) (`brew install xcodegen`)

```bash
# one‑time, if the Metal toolchain isn't installed:
xcodebuild -downloadComponent MetalToolchain
```

## Build & run

```bash
make run          # generate project, build, and launch
# or step by step:
make generate     # xcodegen → Sleepi.xcodeproj
make build        # debug build
make test         # run the SleepiKit unit tests
make release      # optimized build
```

The app launches as a **menu‑bar** item (🌙). Open the window from there, import
media or pick a gradient, and click to set your live wallpaper.

## Installing the screensaver

From the app: **Screensaver → Install**, then **Open Screen Saver Settings** and
choose *SleepiSaver*. (macOS owns the idle timer, so the start delay is set
there.) The app bundles the `.saver` and copies it to `~/Library/Screen Savers/`.

## Architecture

```
SleepiKit (framework)         shared by app + screensaver
├─ Model        ContentItem · GradientConfig · AppSettings · LibraryManifest
├─ Library      LibraryManager (import, thumbnails, JSON manifest)
├─ Render       WallpaperRenderer protocol → Video / AnimatedImage / Gradient / Static
├─ Gradient     Shaders.metal (fbm + domain warp) · presets
├─ Display      WallpaperWindow (desktop level) · DisplayManager (per‑screen)
├─ Power        PlaybackPolicy (pure) · PowerMonitor (sleep/lock/battery/occlusion)
└─ Shared       ContentStore · JSONStore · Logger

Sleepi (app)                  LSUIElement menu‑bar agent + SwiftUI Liquid‑Glass UI
SleepiSaver (.saver)          ScreenSaverView reusing SleepiKit renderers
```

State is shared via `~/Library/Application Support/Sleepi/` (manifest + media +
settings) — both the app and the screensaver are non‑sandboxed and run as you, so
no App Group is required.

### Resource discipline

`PlaybackPolicy` is a pure function of environment + preferences (fully unit
tested). `PowerMonitor` feeds it from `NSWorkspace` sleep notifications, the
screen lock distributed notifications, IOKit power‑source changes, and
`NSWindow.occlusionState`. When it says *don't render*, every renderer pauses
(AVPlayer pauses; `MTKView.isPaused = true`) — zero decode/GPU work.

## What's verified vs. needs your eyes

| Verified automatically | Needs a human (GUI) |
|---|---|
| Builds all 3 targets · 35 unit tests pass | Visual look of the live wallpaper |
| Correct bundle packaging (framework, `default.metallib`, embedded `.saver`) | Screensaver activation in System Settings |
| Clean runtime bootstrap (no crash, library seeded, wallpaper applied) | Multi‑monitor appearance |

## Roadmap

- [ ] Static **login‑window background** (admin‑only)
- [ ] **Per‑display** independent content (dual‑screen)
- [ ] **Community catalogue** sourcing & management
- [ ] GIF→HEVC transcode‑on‑import (lighter playback)
- [ ] Notarized release + auto‑update

## Distribution notes

Sleepi is **non‑sandboxed** (desktop‑window placement and screensaver install are
incompatible with the App Store sandbox). Local builds sign **ad‑hoc**; for
sharing, set a `DEVELOPMENT_TEAM`, enable Hardened Runtime, and notarize.

## License

[GPL‑3.0](LICENSE) © 2026 Sleepi contributors. Free and open source.
