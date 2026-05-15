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
- Provider 兼容类型选择：Anthropic-compatible / OpenAI-compatible。
- Base URL、API Key、Keychain account、Claude 模型映射和 Codex profiles 的设置界面。
- API Key 输入后可显式保存到 macOS Keychain；保存前需要账号核对、Keychain 写入确认和 `KEYCHAIN` 短语确认，保存后界面会清空明文输入框。
- Dashboard 状态页展示 Proxy、LaunchAgent、证书、本机分流路径和准备状态。
- 验证页展示 `/health`、`/dashboard`、`/telemetry/summary` 与四类客户端 health URL。
- 配置预览展示 Claude CLI、Claude Desktop gateway 和 Codex TOML 片段。
- Keychain 读写封装和日志脱敏工具。
- 代理文件安装器。
- Claude/Codex 配置字符串生成。
- LaunchAgent plist 字符串生成，以及 `bootstrap`、`kickstart`、`print`、`bootout` 命令规划。
- 证书生成与信任命令规划。
- Verification URL 与状态汇总模型。
- 本机安装计划生成：复制代理文件、写 runtime config、准备证书配置、写 LaunchAgent plist、准备验证端点。
- 安全文件准备：可在注入的临时目录中准备代理文件、`proxy.env`、`openssl-server.cnf` 和 LaunchAgent plist，用于测试和审查。
- 安装安全层：支持脱敏 dry-run diff、backup manifest、带目标目录白名单的 rollback 和 `INSTALL` 确认门禁。
- 验证页展示 dry-run diff、安装计划、安全边界和执行门禁。

## 安全约束

- 真实 API Key 存入 macOS Keychain。
- Claude/Codex 配置不写真实 API Key。
- LaunchAgent plist 不写真实 API Key。
- App 日志和代理 telemetry 不记录 prompt、response、Authorization、Cookie 或真实 key。
- 当前开发阶段不得修改本机真实 `~/.codex/config.toml`、`~/.claude/settings.json`、Claude Desktop config、`~/Library/LaunchAgents` 或生产 Keychain 项。
- 自动化测试不会写生产 Keychain 项；Keychain 单元测试只使用 `CJLocalProxyTests` 测试 service/account。
- Provider key 保存按钮在确认门禁未满足时禁用；状态层也会拒绝未确认的 Keychain 写入。
- 安装编排测试必须传入临时 `InstallationEnvironment`，不得使用默认真实用户目录执行写入。
- 当前 App 只展示安装计划和命令预览，不自动执行 `launchctl`、`security add-trusted-cert` 或 `openssl`。
- `InstallationSafetyService` 的备份和回滚测试只使用临时目录；rollback 调用必须传入 allowed target roots；真实安装按钮后续接入前必须继续要求显式确认、备份和可回滚 manifest。

## 测试环境说明

当前开发机器使用 CommandLineTools，没有完整 Xcode，也没有 XCTest。SwiftPM tests 使用 Swift Testing；`Package.swift` 的 test target 显式加入了 CommandLineTools 的 `Testing.framework` 和 `lib_TestingInterop.dylib` rpath。
