<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="Capacity Dock">
</p>

<h1 align="center">Capacity Dock</h1>

<p align="center">
  AI quota rings on the edge of your screen.<br>
  See real Claude, Codex, Cursor, Grok, and other usage at a glance; hover for details and running tasks.
</p>

<p align="center">
  <a href="https://github.com/Dmao233/capacity-dock/releases/latest"><img src="https://img.shields.io/github/v/release/Dmao233/capacity-dock" alt="Release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT"></a>
  <a href="README.md"><img src="https://img.shields.io/badge/文档-中文-lightgrey.svg" alt="中文"></a>
</p>

<p align="center">
  <a href="https://github.com/Dmao233/capacity-dock/releases/latest"><b>Download</b></a>
  ·
  <a href="#features">Features</a>
  ·
  <a href="#install-and-update">Install</a>
  ·
  <a href="#usage">Usage</a>
  ·
  <a href="#providers-and-data">Data sources</a>
  ·
  <a href="#releases">Releases</a>
  ·
  <a href="README.md">中文</a>
</p>

<p align="center">
  <img src="assets/demo.gif" width="420" alt="Hover expands the rail and opens the detail card">
</p>

<p align="center">
  <img src="assets/screenshots/rest-close.png" width="200" alt="Rest close-up: quota ring and percentage">
  &nbsp;
  <img src="assets/screenshots/rest.png" width="200" alt="Rest: one preferred ring on the right edge">
  &nbsp;
  <img src="assets/screenshots/hover.png" width="200" alt="Hover: selected providers expanded">
  &nbsp;
  <img src="assets/screenshots/hover-detail.png" width="200" alt="Detail card: quota, reset time, plan">
</p>

## Highlights

- **Real quotas only**: reads the CLIs and apps you are already signed in to; unbound providers show `-`, and usage is never invented.
- **Two rings, two limits**: the outer ring is the weekly quota, the inner ring the 5-hour window; color by usage or by ring.
- **Running tasks**: listed at the bottom of the detail card, grouped by project, styled after the Claude sidebar.
- **Menu-bar bill**: today’s API-equivalent estimate and API balances stay in the menu bar; click for a Today / 7 Days / This Month overview.
- **One-click updates**: About downloads and installs new releases with verification and automatic rollback.
- **Light on resources**: local logs are parsed incrementally; the minute scan takes about 0.07 s.

## Features

### Edge rail

| | |
| --- | --- |
| Docking | Left / right / top / bottom edge, or drag into the desktop for a rounded pill; shown on every Space |
| Rest and hover | Rest shows the preferred ring; hover expands the selected providers; right-click to keep it expanded |
| Rings | Weekly outer ring plus a 5-hour inner ring where available; color by usage or by ring, custom colors, system accent by default |
| Look | Graphite (default) or Liquid Glass material; circle or squircle gauges; live preview in Settings |

### Detail card

| | |
| --- | --- |
| Quotas | Grouped list with large percentages, bars, reset time and countdown, and the plan badge |
| Claude cloud credits | Remaining Cloud credits, spent share, and expiry date |
| Running tasks | Grouped by project, one line per task; Claude tasks use the desktop app’s session titles; hidden when nothing is running |
| Connection | Clear actions and guidance when a provider needs connecting or signing in again |

### Menu bar and usage overview

| | |
| --- | --- |
| Menu bar | Monochrome icon plus amounts: ¥ / $ for API balances, a flame before today’s estimate; left-click for the overview, right-click for Settings |
| Period summaries | Cost, call count, and input / output / cache totals for Today / 7 Days / This Month |
| Charts | Token composition, a 30-day trend, and an 81-day activity heatmap with active days, longest streak, and peak day; hover for per-model usage and cost |
| Breakdown | Group by model or provider and expand token details |
| Appearance | Dark by default, or light / follow system; system accent color; honors Reduce Motion |
| Currencies | 19 display currencies including USD, CNY, and EUR, with cached rates; source estimates stay in USD; can sync CodeBurn’s currency setting |

### API balances

Balances for DeepSeek official accounts and custom HTTPS relays can appear in the menu bar or as a ring on the rail. Keys are stored in the macOS Keychain. See [API balance setup](#api-balance-setup) below.

### Settings and updates

| | |
| --- | --- |
| Settings window | System sidebar: General / Usage / API 账户 (API accounts) / About / each provider |
| Updates | About → **Download and Install**: checked against `SHA256SUMS`, version and code signature verified, the old app restored if replacing fails, relaunch when done |
| Language | Simplified Chinese when that is the system language, English otherwise |

## Install and update

Needs **macOS 14 Sonoma** or later, on Apple Silicon or Intel.

Download one from [Releases](https://github.com/Dmao233/capacity-dock/releases/latest):

| File | Use |
| --- | --- |
| `CapacityDock-*.pkg` | Double-click to install into `/Applications`; opens when done |
| `CapacityDock-*.dmg` | Open and drag the app to **Applications** |
| `CapacityDock-*.zip` | Unzip and move `CapacityDock.app` into `/Applications` or `~/Applications` |

The app is ad-hoc signed. Gatekeeper may block the first launch after a browser download: **right-click → Open** the package or app in Finder, or:

```bash
xattr -d com.apple.quarantine ~/Downloads/CapacityDock-*.pkg
```

The app has no Dock icon, only a menu-bar item.

**Updating**

- 0.3.7 and later: Settings → About → **Download and Install**.
- 0.3.6 and earlier: install a newer release by hand once; later updates work from About.
- If the app’s folder isn’t writable, About offers **Open Release Page** instead.
- Each build has a different ad-hoc signature, so macOS may ask for Keychain access again after an update; choose **Always Allow**.

## Usage

1. First launch docks to the right edge with Grok as the preferred ring; change it in Settings → General.
2. Rest the pointer on the rail: after a short delay the other rings expand and the detail card opens inward.
3. Left-click a ring to make it preferred and show its details. A click does not pin the expansion.
4. Move away: the card closes; without Keep Expanded the rail retracts to one ring.
5. Right-click the rail: **Keep Expanded**, **Dock to Edge** (left / right / top / bottom), **Hide Capacity Dock** (restore from the menu-bar item).
6. Drag the rail to change edges; drag it into the desktop for a pill.
7. Menu-bar item: left-click for the usage overview, right-click for Settings.

## Providers and data

Most providers are read from CLIs or apps already signed in on this Mac; credentials are not copied elsewhere.

| Provider | How it connects |
| --- | --- |
| Claude | Automatic when `~/.claude/.credentials.json` exists; Keychain-only logins need Connect once in the detail card. The Claude CLI refreshes the token; if it expires, send any message with `claude` |
| Codex | Automatic when `~/.codex/auth.json` exists (`codex login`) |
| Cursor | Reads the local session of a signed-in Cursor.app |
| Grok | Automatic when `~/.grok/auth.json` exists (`grok login`) |
| Gemini | Reads `~/.gemini/oauth_creds.json` |
| Copilot | Reads a GitHub token from Copilot, `gh`, or the environment |
| Antigravity | Probes the local language server / `agy` |
| Kimi Code | Reads `~/.kimi-code/credentials/kimi-code.json` |
| ClinePass | Paste an API key in Settings, then Save and Connect |
| Z.ai | API key in Settings, or a local Pi login |

**Cost estimates** come from local token logs for Codex, Claude, Grok, Cursor, and Cursor Agent. Amounts are **API-equivalent estimates, not subscription bills or actual charges**. Unpriced models count usage without being treated as free.

<details>
<summary><b>Override quotas by hand (quota.json)</b></summary>

Quotas written in this file override what the app reads:

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

`percent` ranges from 0 to 1. After saving, click **Reload quota.json** in Settings or restart the app.

</details>

<details>
<summary><b id="api-balance-setup">API balance setup</b></summary>

In Settings → **API 账户** (API accounts), click Add Account, fill in a DeepSeek official account or a custom relay, then Save and Query. The key goes into the macOS Keychain. When editing, leave the key empty to keep it; changing the endpoint requires re-entering the key.

- **DeepSeek**: uses the official `/user/balance`, keeps CNY / USD as returned, and shows topped-up and granted balances.
- **Custom relay**: an HTTPS GET endpoint with `Authorization: Bearer <key>`. Configure the full URL, the amount’s JSON path (e.g. `data.balance`, `data.0.quota`), the currency, and a unit divisor — `100` for amounts in cents; follow the relay’s docs for custom quota units. Cookies, POST, extra auth headers, and scripts are not supported.
- **Display**: accounts are summed per currency and never mixed; the total shows `—` while any account hasn’t been fetched. Balances have no cap, so no percentage is shown.
- **Refresh**: about once a minute, backing off to five minutes on failure, or on demand. `↻` marks a last-known balance. 15 s timeout, 256 KiB response limit, and credentials are not forwarded on redirects.
- Today’s cost in the menu bar is still the local API-equivalent estimate; balances are never added to it.

</details>

## Releases

See the [CHANGELOG](CHANGELOG.md) for everything.

| Version | Highlights |
| --- | --- |
| 0.3.8 | Claude detail card shows Cloud credits: remaining dollars, spent share, expiry date |
| 0.3.7 | One-click download and install from About; running tasks restyled after the Claude sidebar; actionable hint when Claude credentials expire |
| 0.3.6 | Shell back to the 0.3.3 shape; new app icon |
| 0.3.5 | 22pt shell corners restored; the hover settings button sits past the shell’s end |
| 0.3.4 | 5-hour inner ring and custom ring colors; redesigned detail card, usage panel, and Settings; incremental log parsing; Opus 5.5 / GPT-6 Sol pricing; monochrome menu-bar icon |
| 0.3.2 | DeepSeek and custom relay balances; task cards size to their content |
| 0.3.1 | Menu-bar usage overview, trend and activity charts, 19 display currencies |

## Build from source

Needs **Swift 6** (bundled with Xcode 16, or from [swift.org](https://www.swift.org/install/macos/)).

```bash
git clone https://github.com/Dmao233/capacity-dock.git
cd capacity-dock
swift test
Scripts/package-app.sh 0.3.8
open .build/dist/CapacityDock.app
```

For day-to-day work, `swift run`.

```
Sources/CapacityDock/     rail, detail card, provider readers, bill, settings, updates
Tests/CapacityDockTests/  Swift Testing unit tests
Scripts/package-app.sh    builds the ad-hoc-signed .app / pkg / dmg / zip
assets/                   app icon, screenshots, demo animation
```

Pushing a `v*` tag runs GitHub Actions: tests first, then packaging and the Release.

## Credits

- The rail geometry, hover, and detail card come from [CodeBurn](https://github.com/getagentseal/codeburn)’s Capacity Dock (MIT); see [NOTICE](NOTICE).
- The usage overview follows CodeBurn’s layout, hover details, and caching; the activity squares follow [Rare UI](https://www.rareui.com/components/githubactivity), rebuilt in native SwiftUI.
- Design file: [CodeBurn Capacity Dock on Figma](https://www.figma.com/design/RxGVxLJ3okxSKYnquk4ysI/CodeBurn-Capacity-Dock)

## License

[MIT](LICENSE). Copyright (c) 2026 AgentSeal, CenFangyu.
