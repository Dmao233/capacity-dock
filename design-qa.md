# 0.3.1 菜单栏消耗概览验证记录

范围：420 × 660 pt 的菜单栏弹出面板，以及复用同一组件的设置消耗页；保留既有边缘配额环样式。验证日期：2026-09-07。

## 交互与视觉

- 默认深色紫色，菜单栏与通用 / 消耗 / 关于 / 服务商页共享背景和强调色；仍可选择浅色青绿或跟随系统。原生字体、等宽金额、固定币种页脚，下方明细独立滚动。
- 今天 / 近 7 天 / 本月控制汇总和模型、服务商列表，实机切换均有数据。
- 趋势独立显示近 30 天，选择今天也能查看历史柱；悬停显示当天模型用量和估算金额。
- 活动使用近 81 天、三行二十七列。按 [Rare UI GitHub Activity](https://www.rareui.com/components/githubactivity) 的 11×11 方块、3 间距、3 圆角及四档颜色实现，保留缺失数据标记和悬停明细。
- 已对照原组件、选定视觉方向与实机截图检查整体、方块局部和悬停浮层。修正了初版单日活动、过大的矩形/方块、重复服务商筛选、英文页脚及图表打开崩溃。
- 周期切换保持左对齐，图表切换居中，复用滑动选中和悬停反馈；模型 / 服务商指示线同步过渡。
- 使用现有服务商图标和系统符号；刷新动画空闲时停止，尊重减少动态效果。
- 设置入口已统一到真实设置窗口，移除系统空白入口；首次在调用所在屏幕可用区域定位，窗口样式不再异步重设位置。小屏幕标题栏和多屏原点由几何测试覆盖。
- 修正右键菜单的视图坐标和面板层级；菜单跟踪期间暂停悬停伸缩。切换服务商先清空旧任务，再计算详情高度，避免无任务 Cursor 沿用旧高度。
- 活动的三行布局、81 天范围与原组件默认日历布局不同，来自用户最终确认。下方已有模型/服务商明细，不额外复制 GitHub 仓库列表。

## 数据和性能

读取实现参考 [CodeBurn](https://github.com/getagentseal/codeburn) 的文件指纹缓存、内存缓存和任务复用策略，保持本项目已有计价语义。

- 历史扫描按 64 KB 读取，并为每块释放 Foundation 临时对象，避免在整个扫描结束前累积所有临时数据。
- 缓存没有变化时不写盘；编码逐日志条目释放临时对象，缓存事件在生成前按周期筛选。回归覆盖重复保存、失败重试、转义路径和时间边界。
- 共享串行日志读取器，合并重复任务，缓存每个周期的完成结果，支持大于通用 8 MB 文件上限的日志缓存。
- 同一大型日志样本中，旧扫描采样物理占用 15.9 GB；修正后冷扫描采样为 58 MB，当时峰值 110.7 MB。冷周扫描约 120 秒；暖缓存今天 / 周 / 月分别约 1.08 / 1.16 / 0.93 秒。
- 完整应用在多次周期切换后采样物理占用 496.1 MB，该次进程峰值 1.1 GB。上述扫描与完整应用测量不能混用，也不构成长期常驻内存保证。
- 最新后台一分钟检查版本：连续 80.31 秒采样，CPU 时间 2.74 秒，平均约单核 3.41%；瞬时采样 0.2%–55.4%（包含刷新）。随后物理内存 199.4 MB，进程历史峰值 1.7 GB。该样本没有证明启动峰值已解决，也不构成长期耐久保证。
- 账单使用真实本机日志，不填入虚构历史。未知模型保留 token 用量；金额明确标为 API 等价估算，不是订阅扣费。

## 发布前检查

- `swift test -c release`：190 项测试、18 个套件通过。
- 覆盖日期/DST、81 天活动与 30 天趋势投影、缺失数据、模型身份、每日模型汇总、未知价格、汇率、缓存有效期、大缓存及流式边界。
- `Scripts/package-app.sh 0.3.1`：生成 arm64 + x86_64 通用二进制，最低 macOS 14.0，PKG / DMG / ZIP 和 SHA256SUMS。
- ZIP 解压后的应用严格签名、版本号检查通过；ZIP 完整性、DMG 校验、PKG 版本元数据和三个文件的 SHA-256 检查通过。
- iCloud 可向工作目录内的 `.app` 副本附加 Finder 属性，因此以归档解压到本地临时目录后的签名检查为准。
- 实机验证后退出重复测试实例，日常只保留一个应用入口。

截图和原始本机诊断不随公开仓库发布。设置消耗页的深色主题、侧栏、居中图表切换，以及今天 / 七天 / 本月数据已实机检查；周期按钮无障碍名称正确，Grok 连接状态已恢复。通用 / 关于 / 服务商复用根主题配置；右键菜单在不同停靠边缘和多屏下仍需更广泛人工验证。长期耐久测试未包含在上述验证中。

final result: validated with the limitations above

## API balance development pass — 2026-09-10

- Added DeepSeek and explicit HTTPS GET / Bearer / JSON relay balance configuration. Existing local-log period estimates remain unchanged; no claim of actual API debits.
- `swift test -c release`: 200 tests across 20 suites passed, including offline HTTP fixtures, invalid / absent balances, decimal unit conversion, currency aggregation and cache invalidation.
- `Scripts/package-app.sh 0.3.2-dev`: universal build/package succeeded. Installed ZIP extraction passes strict/deep codesign verification; architectures are arm64 and x86_64.
- CUA confirmed the new API account sidebar entry in the running Settings window. Further visual review was interrupted by user interaction; no claim of full live-account UI verification.
- No existing grok-app credential was read or imported. Real DeepSeek / relay balance queries remain pending credentials entered by the user in the application; specific relay protocol compatibility depends on its API documentation.

## Flexible running-task card — 2026-09-10

- Removed the three-task truncation at both snapshot and view boundaries. Active cards widen to 340 pt at 100%, titles wrap, and the card measures its content before fitting to the target screen; excess content scrolls. Empty task lists return to the compact card.
- Task rows share one activity animation, and unchanged task snapshots no longer write view state. Local activity polling frequency and log readers are unchanged.
- `swift test -c release`: 203 tests in 20 suites passed. New checks cover retaining 25 tasks, wrapped-content height, constrained screens, and idle/active widths.
- Universal `0.3.2-dev` packaging and installed ZIP-extraction strict/deep signature verification passed; canonical application restarted with one instance.
- CUA could capture the rail but not reliably the transient detail card. Live multi-task scrolling and long-title visual acceptance remain for user testing; automated layout checks are not presented as full visual verification.

## Account editor and dismiss race — 2026-09-10

- Replaced the reset-only Add action and always-visible form with an item-bound sheet shared by Add and Edit. The sheet focuses a clearly outlined key field, keeps Save/Cancel visible, and presents validation errors locally.
- Fixed the adaptive card regression: clearing active tasks during hide emitted a content-height callback, which called immediate layout and canceled the dismissal animation. Dismissal is now marked before task cleanup; layout/height callbacks ignore closing cards and repeated exits join the fade. Explicit re-entry still restores the card.
- Existing `swift test -c release`: 203 tests in 20 suites passed. Universal packaging and installed ZIP-extraction strict/deep signature verification passed.
- CUA verified Add opens the sheet, empty-key Save shows the required-key error, and Cancel returns to an unchanged empty account list. After subsequent user interaction, a DeepSeek balance was visibly present in the usage popover. No user key was entered or read by the agent.
- Further CUA interaction stopped after user activity was detected. The mouse-leave dismissal path is source-verified; live hover-exit acceptance remains for the user.
