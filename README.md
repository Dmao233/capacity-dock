<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="Capacity Dock">
</p>

<h1 align="center">Capacity Dock</h1>

<p align="center">
  贴在屏幕边缘的 AI 额度环。<br>
  Claude、Codex、Cursor、Grok 等真实用量一眼可见，悬停展开详情和正在运行的任务。
</p>

<p align="center">
  <a href="https://github.com/Dmao233/capacity-dock/releases/latest"><img src="https://img.shields.io/github/v/release/Dmao233/capacity-dock" alt="Release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT"></a>
  <a href="README.en.md"><img src="https://img.shields.io/badge/docs-English-lightgrey.svg" alt="English"></a>
</p>

<p align="center">
  <a href="https://github.com/Dmao233/capacity-dock/releases/latest"><b>下载</b></a>
  ·
  <a href="#功能">功能</a>
  ·
  <a href="#安装与升级">安装与升级</a>
  ·
  <a href="#使用">使用</a>
  ·
  <a href="#服务商与数据来源">数据来源</a>
  ·
  <a href="#版本记录">版本记录</a>
  ·
  <a href="README.en.md">English</a>
</p>

<p align="center">
  <img src="assets/demo.gif" width="420" alt="悬停展开额度栏并打开详情">
</p>

<p align="center">
  <img src="assets/screenshots/rest-close.png" width="200" alt="待机特写：额度环和百分比">
  &nbsp;
  <img src="assets/screenshots/rest.png" width="200" alt="待机：贴在右缘的一枚首选环">
  &nbsp;
  <img src="assets/screenshots/hover.png" width="200" alt="悬停：展开已选服务商">
  &nbsp;
  <img src="assets/screenshots/hover-detail.png" width="200" alt="详情卡：额度、重置时间、套餐">
</p>

## 亮点

- **只看真实额度**：读本机已登录的 CLI / 应用，没登录就显示 `-`，从不编造用量。
- **双环一眼分清**：外环是周额度，内环是 5 小时额度；颜色可按用量或按圆环设置。
- **正在运行的任务**：详情卡底部按项目分组列出，样式参照 Claude 侧栏。
- **菜单栏账单**：今日 API 等价估算和 API 余额常驻菜单栏，点开是今天 / 近 7 天 / 本月的消耗概览。
- **一键更新**：关于页发现新版本可直接下载安装，经过校验，失败自动回滚。
- **几乎不占资源**：本机日志增量解析，每分钟扫描约 0.07 秒。

## 功能

### 侧边额度栏

| | |
| --- | --- |
| 停靠 | 贴在屏幕左 / 右 / 上 / 下，或拖到桌面中间变成圆角胶囊；在所有 Space 都显示 |
| 待机与展开 | 待机只留首选环；悬停展开已选服务商，右键可设为常驻展开 |
| 圆环 | 外环周额度，有 5 小时窗口的服务商加一圈内环；“按用量”或“按圆环”配色，可自定义颜色，默认跟随系统强调色 |
| 外观 | Graphite（默认）或 Liquid Glass 材质；圆形或超椭圆圆环；设置里可实时预览 |

### 详情卡

| | |
| --- | --- |
| 额度 | 分组列表：大号百分比、进度条、重置时间和倒计时、套餐标签 |
| Claude 云端额度 | 显示 Cloud credits 的剩余金额、已用比例和到期日期 |
| 运行任务 | 按项目分组，每个任务一行；Claude 任务显示桌面 App 的会话标题；没有运行中的任务时不显示 |
| 连接状态 | 需要连接或重新登录时直接给出操作按钮和说明 |

### 菜单栏与消耗概览

| | |
| --- | --- |
| 菜单栏 | 单色图标加金额：API 余额用 ¥ / $，今日估算前带火焰图标；左键打开消耗概览，右键打开设置 |
| 周期汇总 | 今天 / 近 7 天 / 本月的金额、调用次数、输入 / 输出 / 缓存用量 |
| 图表 | 用量构成、近 30 天趋势、近 81 天活动热力图（附活跃天数、最长连续、单日峰值）；悬停看当天各模型用量和金额 |
| 明细 | 按模型或服务商分组，可展开 token 明细 |
| 外观 | 默认深色，可切换浅色或跟随系统；强调色跟随系统；动效遵循“减少动态效果” |
| 币种 | USD、CNY、EUR 等 19 种展示币种，缓存汇率，原始估算保持 USD，可同步 CodeBurn 的币种设置 |

### API 余额

DeepSeek 官方账户和自定义 HTTPS 中转站的余额，可以显示在菜单栏，也可以作为侧边栏的一个“环”。密钥存放在 macOS 钥匙串。配置方法见下方 [API 余额配置](#api-余额配置)。

### 设置与更新

| | |
| --- | --- |
| 设置窗口 | 系统侧栏样式：通用 / 消耗 / API 账户 / 关于 / 各服务商 |
| 自动更新 | 关于页“下载并安装”：按 `SHA256SUMS` 校验，检查版本号和代码签名，替换失败自动恢复旧版，装好自动重开 |
| 语言 | 系统语言是简体中文时显示中文，其余为英文 |

## 安装与升级

需要 **macOS 14 Sonoma** 或更新，Apple Silicon 和 Intel 都支持。

从 [Releases](https://github.com/Dmao233/capacity-dock/releases/latest) 下载其一：

| 文件 | 用法 |
| --- | --- |
| `CapacityDock-*.pkg` | 双击安装到 `/Applications`，装完自动打开 |
| `CapacityDock-*.dmg` | 打开后把应用拖到 **Applications** |
| `CapacityDock-*.zip` | 解压后把 `CapacityDock.app` 拖进 `/Applications` 或 `~/Applications` |

应用是 ad-hoc 签名。浏览器下载后 Gatekeeper 可能拦一次：在 Finder 里对安装包或应用 **右键 → 打开**，或者：

```bash
xattr -d com.apple.quarantine ~/Downloads/CapacityDock-*.pkg
```

应用不出现在 Dock，只在菜单栏有一个图标。

**升级**

- 0.3.7 及以上：设置 → 关于 → **下载并安装**。
- 0.3.6 及更早：手动安装一次新版本，之后就能在关于页一键更新。
- 应用所在文件夹不可写时，关于页会改为提供“打开发布页”。
- 每次构建的 ad-hoc 签名不同，更新后第一次读取钥匙串时 macOS 可能再次请求授权，选“始终允许”即可。

## 使用

1. 首次启动停在屏幕右缘，首选环是 Grok，可在设置 → 通用里修改。
2. 指针停在额度栏上：稍等片刻展开其余环，并向内打开详情卡。
3. 左键点某个环：设为首选并显示它的详情。左键不会让展开状态固定下来。
4. 指针移开：详情卡关闭；没开常驻展开时，额度栏收回成一个环。
5. 右键额度栏：**常驻展开**、**停靠到边缘**（左 / 右 / 上 / 下）、**隐藏侧边额度栏**（之后从菜单栏图标恢复）。
6. 拖动额度栏可以换边；拖到桌面中间变成胶囊。
7. 菜单栏图标：左键打开消耗概览，右键打开设置。

## 服务商与数据来源

多数服务商直接读本机已登录的 CLI 或应用，不会另存一份凭据。

| 服务商 | 连接方式 |
| --- | --- |
| Claude | 有 `~/.claude/.credentials.json` 时自动读取；只存在钥匙串里时，第一次在详情卡点 Connect。token 由 Claude CLI 负责刷新，过期时用 `claude` 发一条消息即可恢复 |
| Codex | 有 `~/.codex/auth.json`（`codex login`）时自动读取 |
| Cursor | 已登录 Cursor.app 时读本地 session |
| Grok | 有 `~/.grok/auth.json`（`grok login`）时自动读取 |
| Gemini | 读 `~/.gemini/oauth_creds.json` |
| Copilot | 读本机 Copilot、`gh` 或环境变量里的 GitHub token |
| Antigravity | 探测本机 language server / `agy` |
| Kimi Code | 读 `~/.kimi-code/credentials/kimi-code.json` |
| ClinePass | 在设置页粘贴 API 密钥后“保存并连接” |
| Z.ai | 设置页 API 密钥，或本机 Pi 登录 |

**消耗估算**：读取 Codex、Claude、Grok、Cursor 和 Cursor Agent 的本机 token 日志，金额是 **API 等价估算，不是订阅账单或实际扣费**。没有定价的模型只计用量，不当作零费用。

<details>
<summary><b>手动覆盖额度（quota.json）</b></summary>

在下面这个文件里手写额度，会覆盖读取到的数据：

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

`percent` 的取值是 0…1。保存后在设置里点“重新加载 quota.json”，或重启应用。

</details>

<details>
<summary><b id="api-余额配置">API 余额配置</b></summary>

在设置 → **API 账户** 点“添加账户”，填写 DeepSeek 官方账户或自定义中转站，再点“保存并查询”。密钥写入 macOS 钥匙串；编辑时密钥留空表示保留原密钥，但改了接口地址就必须重新填写密钥。

- **DeepSeek**：使用官方 `/user/balance`，保留 CNY / USD 原币种，详情里显示充值余额和赠送余额。
- **自定义中转站**：HTTPS GET 接口，鉴权方式为 `Authorization: Bearer <key>`。需要配置完整 URL、金额的 JSON 路径（如 `data.balance`、`data.0.quota`）、币种和单位除数。金额以“分”为单位时除数填 `100`，平台自定义的 quota 单位请按它的文档填写。不支持 Cookie 登录、POST、额外鉴权头或脚本。
- **显示**：多个账户按币种分别汇总，不会把人民币和美元加在一起；有账户还没查询成功时，总额显示 `—`。余额没有上限，所以不显示百分比。
- **刷新**：正常约每分钟一次，失败后退避到五分钟，也可以手动刷新。`↻` 表示显示的是上次的余额。请求超时 15 秒，响应上限 256 KiB，重定向时不转发凭据。
- 菜单栏右侧的今日消耗仍是本机日志的 API 等价估算，左侧的余额不会计入其中。

</details>

## 版本记录

完整记录见 [CHANGELOG](CHANGELOG.md)。

| 版本 | 主要内容 |
| --- | --- |
| 0.3.8 | Claude 详情卡显示 Cloud credits：剩余金额、已用比例、到期日期 |
| 0.3.7 | 关于页一键下载安装；运行任务改为 Claude 侧栏样式；Claude 凭据过期时给出刷新提示 |
| 0.3.6 | 外壳恢复 0.3.3 的形状；新应用图标 |
| 0.3.5 | 外壳圆角回到 22pt；悬停时的设置按钮挂到外壳末端之外 |
| 0.3.4 | 5 小时内环与自定义圆环配色；详情卡、消耗面板、设置窗口重做；日志增量解析；Opus 5.5 / GPT-6 Sol 单价；菜单栏单色图标 |
| 0.3.2 | DeepSeek 与自定义中转站余额；运行任务卡按内容伸缩 |
| 0.3.1 | 菜单栏消耗概览、趋势图与活动热力图、19 种展示币种 |

## 从源码构建

需要 **Swift 6**（Xcode 16 自带，或从 [swift.org](https://www.swift.org/install/macos/) 安装）。

```bash
git clone https://github.com/Dmao233/capacity-dock.git
cd capacity-dock
swift test
Scripts/package-app.sh 0.3.8
open .build/dist/CapacityDock.app
```

日常开发直接 `swift run`。

```
Sources/CapacityDock/     额度栏、详情卡、服务商读取、账单、设置、更新
Tests/CapacityDockTests/  Swift Testing 单元测试
Scripts/package-app.sh    打包 ad-hoc 签名的 .app / pkg / dmg / zip
assets/                   应用图标、截图、演示动图
```

推送 `v*` 标签会触发 GitHub Actions：先跑测试，再打包并发布 Release。

## 致谢

- 额度栏的几何、悬停和详情卡来自 [CodeBurn](https://github.com/getagentseal/codeburn) 的 Capacity Dock（MIT），版权见 [NOTICE](NOTICE)。
- 消耗概览参考了 CodeBurn 的布局、悬停明细和缓存策略；活动方块参考 [Rare UI](https://www.rareui.com/components/githubactivity)，用原生 SwiftUI 实现。
- 设计稿：[CodeBurn Capacity Dock on Figma](https://www.figma.com/design/RxGVxLJ3okxSKYnquk4ysI/CodeBurn-Capacity-Dock)

## 许可

[MIT](LICENSE)。Copyright (c) 2026 AgentSeal、CenFangyu。
