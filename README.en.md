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

Rest shows only the preferred ring. Hover expands the selected set and opens an inward detail card: progress, reset time, plan. Live sessions appear under `Source:` as a workspace label plus the conversation title. The menu bar shows today’s estimated cost. Left-click it for the usage overview; right-click opens Settings.

Rail geometry, hover, and the detail card come from [CodeBurn](https://github.com/getagentseal/codeburn)’s Capacity Dock (MIT). This repository packages that surface as a small, installable app.

## Features

| | |
| --- | --- |
| Edge notch | Dock to left / right / top / bottom, or drag it into a floating pill |
| Quota rings | Rest shows the preferred ring; hover expands the selected set and the detail card |
| Detail | Progress, reset time, plan, connect; live rows show the workspace and conversation title |
| Local logins | Reads Codex, Claude, Cursor, Gemini, Antigravity, Copilot, Kimi Code, and Grok from this Mac; ClinePass and Z.ai can also take a key in Settings |
| Settings | Sidebar for General / Usage / About / providers, plus a GitHub update check |
| Usage overview | Today’s estimate in the menu bar; a compact popover with Today / 7 Days / This Month summaries |
| Charts and details | Token composition, an independent 30-day trend, and an 81-day activity heatmap; hover for daily model usage and estimated cost |
| Models / providers | Switch grouping below the chart and expand token details; currency controls stay visible |
| Appearance | Light, dark, or system theme; centered chart tabs with a sliding selection, number transitions, and row hover feedback; the refresh indicator stops when idle |
| Currencies | 19 display currencies including USD, CNY, and EUR, with cached exchange rates and USD source estimates |
| Menu-bar extra | Left-click for the overview, right-click for Settings; restore a hidden rail from here; no Dock slot |
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
Scripts/package-app.sh 0.3.1
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

## Usage overview (0.3.1)

Click the menu-bar amount to open the bill directly below it. The existing edge rings continue to show subscription quotas.

- **Consistent surfaces:** The menu-bar popover and Settings Usage page share themes, summaries, charts, hover details, currency controls, and cached reads.
- **Period summaries:** Today, 7 Days, and This Month control the main cost, call count, input / output / cache totals, and the model/provider list.
- **Independent trend:** The chart always covers the last 30 days, even with Today selected. Hover a bar for the date, daily total, model usage, and estimated cost.
- **Activity heatmap:** The last 81 days appear as three rows of fixed-size squares with four intensity levels. Hover for daily details. Missing records are distinguished from measured zero usage.
- **Appearance:** Dark violet is the default across the bill and all Settings pages. Use the top-right More menu for light, dark, or system theme, and the footer for currency. Period and chart controls share sliding selection and hover feedback; period controls stay left-aligned and chart controls are centered. Model/provider underlines animate consistently. Animations respect Reduce Motion.
- **Historical loading:** File fingerprints reuse parsed logs, duplicate requests share work, and streaming releases temporary memory promptly. Unchanged caches are not rewritten; per-entry encoding and early period filtering reduce temporary allocations. The first scan of a large history can still take time and shows progress; later period switches reuse caches. Background checks run once per minute, while opening a page uses a 30-second freshness window and manual reload bypasses it.

Local bills read token logs from Codex, Claude, Grok, Cursor, and Cursor Agent. Amounts are **API-equivalent estimates, not subscription bills or actual charges**. This version adds `gpt-6-astra` rates and its long-context tier. Unpriced models retain their usage; unknown prices are not presented as confirmed zero cost.

Currency changes only affect display; source estimates remain in USD. Non-USD displays use exchange rates. If a rate cannot be fetched and no cached rate is available, the previous currency stays selected with an error message. Currency selection also updates the currency fields in `~/.config/codeburn/config.json`, preserving other settings for use alongside CodeBurn.

## API balances (development, unreleased)

Add a DeepSeek account or custom relay under **API 账户** in Settings. Saving stores the key in macOS Keychain and queries the configured balance endpoint. Leave the key empty when editing to retain it; changing the endpoint requires entering the destination's key again.

- A single account shows **provider icon remaining balance | ◉ today's existing cost estimate**. Without API accounts the menu bar stays unchanged.
- The existing today / last seven days / month totals remain local-log API-equivalent estimates, not actual API debits. Balances are never added to those costs.
- DeepSeek uses `/user/balance`, preserving CNY / USD and showing topped-up and granted credits in account details.
- Relays support an HTTPS GET endpoint with Bearer authentication, a JSON amount path (such as `data.balance` or `data.0.quota`), currency, and a unit divisor. Use `100` for cents; consult the relay's documentation for internal quota units.
- No automatic endpoint probing, Cookie authentication, POST, extra authentication headers, or custom scripts. OpenAI-compatible inference does not imply a balance API.
- Multiple accounts aggregate separately by currency. Do not add multiple keys belonging to the same balance account. If any account has no valid result, the total shows `—` rather than a partial sum.
- Refreshes approximately every minute, backing off to five minutes on failure. `↻` marks the previous balance; expand the balance strip for timestamps and errors. Failures never become zero.
- Small separate caches, coalesced serial refreshes, a 15-second request timeout, a 256 KiB response limit, and no credential forwarding on redirects. Balance refreshes do not rescan token logs.

This development version reads balances. It does not infer actual spending from balance changes or implement relay historical debit ledgers.

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
- The usage overview draws on CodeBurn’s layout, hover details, and caching strategy. Activity cells and motion reference [Rare UI](https://www.rareui.com/components/githubactivity), implemented natively in SwiftUI.
- Design: [CodeBurn Capacity Dock on Figma](https://www.figma.com/design/RxGVxLJ3okxSKYnquk4ysI/CodeBurn-Capacity-Dock)

## License

[MIT](LICENSE). Copyright (c) 2026 AgentSeal and CenFangyu.
