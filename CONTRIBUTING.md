# 参与贡献

先看 [README.md](README.md)。英文说明见 [README.en.md](README.en.md)。

## 开发

需要 macOS 14+ 和 Swift 6。

```bash
cd capacity-dock
swift test
swift run
```

打包 `.app`：

```bash
Scripts/package-app.sh 0.2.0
open .build/dist/CapacityDock.app
```

## 约定

- 槽的几何、悬停和详情卡片改动，优先补 `Tests/CapacityDockTests` 里对应的 Swift Testing 用例。
- 中文文案放 `Sources/CapacityDock/Resources/zh-Hans.lproj/Localizable.strings`，英文键就是源字符串。
- 不要把真实 API 密钥、Cookie 或配额抓包写进仓库。
- 提交说明写事：`feat:` / `fix:` / `docs:` / `test:`。

## 许可

贡献默认按 [MIT License](LICENSE) 授权。源码里有从 [CodeBurn](https://github.com/getagentseal/codeburn) 抽出的部分，请保留 [NOTICE](NOTICE) 中的版权声明。
