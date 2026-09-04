<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="Capacity Dock">
</p>

<h1 align="center">Capacity Dock</h1>

<p align="center">
  macOS 屏幕边缘的有机黑槽用量条。<br>
  一眼看 Grok、Claude、Copilot、Codex 等 AI 配额，悬停展开详情。
</p>

<p align="center">
  <a href="https://github.com/Dmao233/capacity-dock/releases/latest"><img src="https://img.shields.io/github/v/release/Dmao233/capacity-dock" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT"></a>
  <a href="README.en.md"><img src="https://img.shields.io/badge/docs-English-lightgrey.svg" alt="English"></a>
</p>

<p align="center">
  <a href="README.en.md">English</a>
  ·
  <a href="#安装">安装</a>
  ·
  <a href="#使用">使用</a>
  ·
  <a href="https://github.com/Dmao233/capacity-dock/releases/latest">下载</a>
  ·
  <a href="LICENSE">MIT</a>
</p>

<p align="center">
  <img src="assets/demo.gif" width="420" alt="悬停展开用量槽并打开详情">
</p>

<p align="center">
  <img src="assets/screenshots/rest.png" width="220" alt="待机：一枚首选环">
  &nbsp;
  <img src="assets/screenshots/hover.png" width="360" alt="悬停：全部环和详情气泡">
</p>

## 这是什么

Capacity Dock 是 macOS 14+ 的菜单栏附属应用，没有 Dock 图标。它把各家 AI 的真实配额贴在屏幕边缘：没登录就是 `-`，不编造用量。

几何、悬停和详情卡片来自 [CodeBurn](https://github.com/getagentseal/codeburn) 的 Capacity Dock（MIT）。本仓库做成可安装的独立小工具。

## 功能

| | |
| --- | --- |
| 边缘用量槽 | 贴在屏幕左 / 右 / 上 / 下，或拖到桌面变成胶囊 |
| 配额环 | 待机只留首选环；悬停展开已选服务商和详情 |
| 详情 | 进度、重置时间、套餐、连接；进行中任务显示会话标题 |
| 本机读取 | Codex、Claude、Cursor、Gemini、Antigravity、Copilot、Kimi Code、Grok 读本机登录；ClinePass、Z.ai 也可在设置里填密钥 |
| 设置 | 左侧边栏：通用 / 关于 / 服务商，可检查更新 |
| 菜单栏入口 | 隐藏后从 `◉` 再打开，不占 Dock |
| 跟桌面走 | 所有 Space 都在，不会钉在第一次出现的那一屏 |
| 中英 | 系统语言是简体中文时用中文 |

## 安装

需要 **macOS 14 Sonoma** 或更新。

### 下载安装包

从 [Releases](https://github.com/Dmao233/capacity-dock/releases/latest) 下载其一：

| 文件 | 用法 |
| --- | --- |
| `CapacityDock-*.pkg` | 双击安装到 `/Applications`，装完会自动打开 |
| `CapacityDock-*.dmg` | 打开后把应用拖到 **Applications** |
| `CapacityDock-*.zip` | 解压后把 `CapacityDock.app` 拖进 `/Applications` |

这是 ad-hoc 签名的通用二进制（Apple Silicon + Intel）。浏览器下载后 Gatekeeper 可能会拦一次：在 Finder 里对 `.pkg` / 应用 **右键 → 打开**，或：

```bash
xattr -d com.apple.quarantine ~/Downloads/CapacityDock-*.pkg
xattr -d com.apple.quarantine /Applications/CapacityDock.app
```

应用是 `LSUIElement`，不会出现在 Dock。菜单栏右侧会有一个 `◉` 入口，用来重新显示、打开设置或退出。

### 从源码构建

需要 **Swift 6**（随 Xcode 16 或 [swift.org](https://www.swift.org/install/macos/)）。

```bash
git clone https://github.com/Dmao233/capacity-dock.git
cd capacity-dock
swift test
Scripts/package-app.sh 0.4.1
open .build/dist/CapacityDock.app
```

日常开发直接：

```bash
swift run
```

## 使用

1. 第一次启动默认停在屏幕右缘，首选环是 Grok（可在设置里改）。
2. 把指针放到槽上：短暂延迟后展开其余环，并打开详情。
3. 左键点某一环：把它设为首选，并显示该服务商详情。左键**不会**钉住展开。
4. 移开指针：详情关掉；若未打开常驻展开，槽收回成一枚环。
5. 右键槽：
   - **常驻展开**：待机就显示全部已选环，详情仍随鼠标关
   - **停靠到边缘**：左 / 右 / 上 / 下
   - **隐藏侧边额度栏**：从屏幕拿掉，用菜单栏入口再打开
6. 点槽外的设置齿轮，或菜单栏里的「侧边额度栏设置…」。左侧是通用 / 关于 / 服务商列表，也可以检查 GitHub 上的新版本。
7. 悬停某家环时，若该服务商 90 秒内有活写入，详情里 `Source:` 下面会出现绿圈和标题，最多 3 条。

拖动槽可以换边。贴到边缘会重新长出勺形接触；拉到桌面中间则变成圆角胶囊，设置条改到尾部。

## 配额数据

多数服务商读本机已经登录的 CLI / 应用，不把来源凭证再存一份。ClinePass 和 Z.ai 用设置页保存的 API 密钥。

| 服务商 | 怎么连上 |
| --- | --- |
| Codex | 本机有 `~/.codex/auth.json`（`codex login`）就会自动拉 |
| Claude | 有 `~/.claude/.credentials.json` 会自动拉；只有钥匙串时，第一次点详情里的 Connect |
| Cursor | 已登录 Cursor.app，读本地 session，走 `api2.cursor.sh` |
| Grok | 本机有 `~/.grok/auth.json`（`grok login`）就会自动拉 |
| Gemini | 读 `~/.gemini/oauth_creds.json` |
| Copilot | 读本机 Copilot / `gh` / 环境变量里的 GitHub token |
| Antigravity | 探活本机 language server / `agy` |
| Kimi Code | 读 `~/.kimi-code/credentials/kimi-code.json` |
| ClinePass | 设置页粘贴 API 密钥后「保存并连接」 |
| Z.ai | 设置页 API 密钥，或本机 Pi 登录 |

未登录显示 `-`。也可以手写覆盖文件：

```
~/Library/Application Support/CapacityDock/quota.json
```

示例见 [`docs/quota.example.json`](docs/quota.example.json)：

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

`percent` 是 0…1。保存后在设置里点「重新加载 quota.json」，或重启应用。本仓库不伪造用量。

## 开发

```
Sources/CapacityDock/     槽、悬停、详情、本机配额、设置
Tests/CapacityDockTests/  Swift Testing，几何 / 交互 / 偏好
Scripts/package-app.sh    打成 ad-hoc 签名的 .app
assets/                   应用图标、真机截图、演示 GIF / MP4
```

改槽的形状或悬停时，请跑：

```bash
swift test
```

## 致谢

- 槽的实现从 [CodeBurn](https://github.com/getagentseal/codeburn) 抽出，版权见 [NOTICE](NOTICE)。
- 设计稿：[CodeBurn Capacity Dock on Figma](https://www.figma.com/design/RxGVxLJ3okxSKYnquk4ysI/CodeBurn-Capacity-Dock)

## 许可

[MIT](LICENSE)。Copyright (c) 2026 AgentSeal、CenFangyu。
