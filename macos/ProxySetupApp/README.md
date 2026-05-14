# macOS 本机代理设置 App

这个 App 用于在本机配置 Claude Code Desktop/CLI 与 Codex App/CLI 的统一 HTTPS 代理。

## 开发运行

```bash
cd macos/ProxySetupApp
swift build
swift test
```

从项目根目录启动 GUI App：

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
```

## 当前能力

- SwiftUI 主窗口和菜单栏入口。
- Provider、模型映射和验证 URL 的设置界面。
- Keychain 读写封装。
- 代理文件安装器。
- Claude/Codex 配置字符串生成。
- LaunchAgent plist 字符串生成。
- 证书生成命令规划。
- Verification URL 与状态汇总模型。

## 安全约束

- 真实 API Key 存入 macOS Keychain。
- Claude/Codex 配置不写真实 API Key。
- LaunchAgent plist 不写真实 API Key。
- App 日志和代理 telemetry 不记录 prompt、response、Authorization、Cookie 或真实 key。
- 当前开发阶段不得修改本机真实 `~/.codex/config.toml`、`~/.claude/settings.json`、Claude Desktop config、`~/Library/LaunchAgents` 或生产 Keychain 项。

## 测试环境说明

当前开发机器使用 CommandLineTools，没有完整 Xcode，也没有 XCTest。SwiftPM tests 使用 Swift Testing；`Package.swift` 的 test target 显式加入了 CommandLineTools 的 `Testing.framework` 和 `lib_TestingInterop.dylib` rpath。
