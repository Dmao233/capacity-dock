<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="Capacity Dock">
</p>

<h1 align="center">Capacity Dock</h1>

<p align="center">
  An organic black notch on the Mac display edge.<br>
  Glance at Grok, Claude, Copilot, Codex, and other AI quotas; hover for the detail card.
</p>

<p align="center">
  <a href="https://github.com/Dmao233/capacity-dock/releases/latest"><img src="https://img.shields.io/github/v/release/Dmao233/capacity-dock" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT"></a>
  <a href="README.md"><img src="https://img.shields.io/badge/docs-简体中文-lightgrey.svg" alt="简体中文"></a>
</p>

<p align="center">
  <a href="README.md">简体中文</a>
  ·
  <a href="#install">Install</a>
  ·
  <a href="#usage">Usage</a>
  ·
  <a href="https://github.com/Dmao233/capacity-dock/releases/latest">Download</a>
  ·
  <a href="LICENSE">MIT</a>
</p>

<p align="center">
  <img src="assets/demo.gif" width="420" alt="Hover expands the notch and opens the detail card">
</p>

<p align="center">
  <img src="assets/screenshots/rest.png" width="220" alt="Rest: one preferred ring">
  &nbsp;
  <img src="assets/screenshots/hover.png" width="360" alt="Hover: all rings and the detail bubble">
</p>

## What it is

Capacity Dock is a macOS 14+ menu-bar accessory (no Dock icon). It parks provider quotas in a black organic notch on the screen edge:

- **Rest** shows only the preferred provider ring
- **Hover** expands the selected set along the bottom scoop and opens an inward detail bubble
- **Keep Expanded** leaves every selected ring visible at rest; the detail card still follows the pointer
- Dock to left / right / top / bottom, or drag it into a floating pill
- Settings live outside the blob: a short arc that follows the scoop, inflating into a gear on hover

This repository packages that surface as a small, buildable app. Rail geometry, hover, and the detail card come from [CodeBurn](https://github.com/getagentseal/codeburn)’s Capacity Dock (MIT). Rings show `-` until you supply real numbers in `quota.json` — no placeholder usage.

## Features

| | |
| --- | --- |
| Organic notch | Top scoop stays locked while height changes |
| Quota rings | Weekly window first; unbound usage is a single `-` |
| Detail bubble | Progress, reset countdown, plan, Connect / Reconnect |
| SuperGrok Heavy | Plan label compact to `Heavy` |
| Right-click menu | Keep Expanded, Dock to Edge, Hide |
| Spaces | Joins every desktop; not pinned to the Space where it first appeared |
| Chinese + English | `zh-Hans` when the system language is Simplified Chinese |

## Install

Needs **macOS 14 Sonoma** or later.

### Download

Grab `CapacityDock-*.zip` from [Releases](https://github.com/Dmao233/capacity-dock/releases/latest), unzip, and drop `CapacityDock.app` into `/Applications` or `~/Applications`.

The build is an ad-hoc-signed universal binary (Apple Silicon + Intel). After a browser download Gatekeeper may block the first launch. Either:

```bash
xattr -d com.apple.quarantine ~/Applications/CapacityDock.app
```

or **Right-click → Open** in Finder.

The app is an `LSUIElement`, so it never appears in the Dock. A `◉` status item can show the rail again, open Settings, or quit.

### Build from source

Needs **Swift 6** (Xcode 16 or [swift.org](https://www.swift.org/install/macos/)).

```bash
git clone https://github.com/Dmao233/capacity-dock.git
cd capacity-dock
swift test
Scripts/package-app.sh 0.1.2
open .build/dist/CapacityDock.app
```

For day-to-day development:

```bash
swift run
```

## Usage

1. First launch docks to the right edge with Grok as the preferred ring (change this in Settings).
2. Park the pointer on the notch: after a short delay it expands and the detail card opens.
3. Left-click a ring to make it preferred and show that provider’s card. A click does **not** pin expansion.
4. Leave the pointer: the card closes; without Keep Expanded the rail retracts to one ring.
5. Right-click the notch:
   - **Keep Expanded**: rest shows every selected ring; the card still closes on leave
   - **Dock to Edge**: Left / Right / Top / Bottom
   - **Hide Capacity Dock**: remove it from the screen; restore from the status item
6. Click the external gear, or **Capacity Dock Settings…** in the status menu. Settings can check GitHub for a newer release.

Drag to change edges. Contact with an edge grows the scoop; pulling it into the desktop turns it into a rounded pill with the settings bar at the tail.

## Quota data

There is no canned usage on first launch; unbound rings show `-`. To feed real numbers, write:

```
~/Library/Application Support/CapacityDock/quota.json
```

See [`docs/quota.example.json`](docs/quota.example.json):

```json
{
  "providers": {
    "grok": {
      "displayName": "Grok",
      "plan": "Heavy",
      "footer": [],
      "windows": [{ "label": "Weekly", "percent": 0.23 }]
    }
  }
}
```

`percent` is 0…1. After saving, click **Reload quota.json** in Settings, or relaunch.

Demo providers include Grok, Claude, Copilot, Codex, Gemini, Kimi Code, Cursor, and Antigravity. Live account adapters still live in the CodeBurn menubar app; this repo stays small and compile-from-source.

## Develop

```
Sources/CapacityDock/     notch, hover, detail, demo quotas, settings
Tests/CapacityDockTests/  Swift Testing for geometry, interaction, preferences
Scripts/package-app.sh    ad-hoc-signed .app
assets/                   app icon, screenshots, demo GIF / MP4
```

After changing the silhouette or hover:

```bash
swift test
```

## Credits

- Extracted from [CodeBurn](https://github.com/getagentseal/codeburn). See [NOTICE](NOTICE).
- Design: [CodeBurn Capacity Dock on Figma](https://www.figma.com/design/RxGVxLJ3okxSKYnquk4ysI/CodeBurn-Capacity-Dock)

## License

[MIT](LICENSE). Copyright (c) 2026 AgentSeal and CenFangyu.
