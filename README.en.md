<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="Capacity Dock">
</p>

<h1 align="center">Capacity Dock</h1>

<p align="center">
  Quota rings on the Mac display edge.<br>
  Glance at real Cursor, Codex, Grok, and other usage; hover for the detail card.
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
  <img src="assets/screenshots/rest-close.png" width="280" alt="Rest close-up: ring and percent">
  &nbsp;
  <img src="assets/screenshots/rest.png" width="280" alt="Rest: one preferred ring on the right edge">
</p>

<p align="center">
  <img src="assets/screenshots/hover.png" width="280" alt="Hover: detail card and selected rings">
  &nbsp;
  <img src="assets/screenshots/hover-detail.png" width="280" alt="Detail: progress, plan, reset time">
</p>

## What it is

Capacity Dock is a macOS 14+ menu-bar accessory with no Dock icon. It parks real AI quotas on the screen edge: unbound rings show `-`, and the app does not invent usage.

Rest shows only the preferred ring. Hover expands the selected set and opens an inward detail card: progress, reset time, plan. Live sessions appear under `Source:` as a workspace label plus the conversation title. Left-click the menu-bar `◉` for the local token bill; right-click opens Settings.

Rail geometry, hover, and the detail card come from [CodeBurn](https://github.com/getagentseal/codeburn)’s Capacity Dock (MIT). This repository packages that surface as a small, installable app.

## Features

| | |
| --- | --- |
| Edge notch | Dock to left / right / top / bottom, or drag it into a floating pill |
| Quota rings | Rest shows the preferred ring; hover expands the selected set and the detail card |
| Detail | Progress, reset time, plan, connect; live rows show the workspace and conversation title |
| Local logins | Reads Codex, Claude, Cursor, Gemini, Antigravity, Copilot, Kimi Code, and Grok from this Mac; ClinePass and Z.ai can also take a key in Settings |
| Settings | Sidebar for General / Usage / About / providers, plus a GitHub update check |
| Menu-bar extra | Left-click `◉` for the bill, right-click for Settings; hide the rail and restore it from here; no Dock slot |
| Spaces | Follows every desktop; not pinned to the Space where it first appeared |
| Chinese + English | Simplified Chinese when that is the system language |

## Install

Needs **macOS 14 Sonoma** or later.

### Download

From [Releases](https://github.com/Dmao233/capacity-dock/releases/latest) grab one of:

| File | How to install |
| --- | --- |
| `CapacityDock-*.pkg` | Double-click to install into `/Applications`, then it launches |
| `CapacityDock-*.dmg` | Open and drag the app onto **Applications** |
| `CapacityDock-*.zip` | Unzip and drop `CapacityDock.app` into `/Applications` |

The build is an ad-hoc-signed universal binary (Apple Silicon + Intel). After a browser download Gatekeeper may block the first launch: **Right-click → Open** the `.pkg` or app, or:

```bash
xattr -d com.apple.quarantine ~/Downloads/CapacityDock-*.pkg
xattr -d com.apple.quarantine /Applications/CapacityDock.app
```

The app is an `LSUIElement`, so it never appears in the Dock. A `◉` status item can show the rail again, open Settings, or quit.

### Build from source

Needs **Swift 6** (Xcode 16 or [swift.org](https://www.swift.org/install/macos/)).

```bash
git clone https://github.com/Dmao233/capacity-dock.git
cd capacity-dock
swift test
Scripts/package-app.sh 0.2.0
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
6. Click the external gear, or right-click the menu-bar `◉` for Settings. The sidebar has General / Usage / About / providers, and can check GitHub for a newer release. Left-click `◉` to open the local token bill under the icon.
7. Hover a ring: if that provider is in use, a green live dot, workspace label, and conversation title appear under `Source:`, at most three rows.

Drag to change edges. Contact with an edge grows the scoop; pulling it into the desktop turns it into a rounded pill with the settings bar at the tail.

## Quota data

Most providers are read from the login already on this Mac. Source credentials are not copied into Capacity Dock’s Keychain. ClinePass and Z.ai use an API key saved from Settings.

| Provider | How it connects |
| --- | --- |
| Codex | Auto if `~/.codex/auth.json` exists (`codex login`) |
| Claude | Auto if `~/.claude/.credentials.json` exists; Keychain-only logins need Connect once |
| Cursor | Reads the signed-in Cursor.app session via `api2.cursor.sh` |
| Grok | Auto if `~/.grok/auth.json` exists (`grok login`) |
| Gemini | Reads `~/.gemini/oauth_creds.json` |
| Copilot | Reads a GitHub token already on this Mac (Copilot / `gh` / env) |
| Antigravity | Probes a running language server / `agy` |
| Kimi Code | Reads `~/.kimi-code/credentials/kimi-code.json` |
| ClinePass | Paste an API key in Settings, then Save & Connect |
| Z.ai | Settings API key, or an existing Pi login |

Unbound rings show `-`. You can still overlay:

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

`percent` is 0…1. After saving, click **Reload quota.json** in Settings, or relaunch. This app does not invent usage.

## Develop

```
Sources/CapacityDock/     notch, hover, detail, live quotas, settings
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
