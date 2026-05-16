# Claude Code Desktop 第三方 API 接入 Handoff

更新时间：2026-05-16

本文记录本次会话在项目 `/Users/chjia/Documents/Codex/2026-05-11/claude-code-app-api` 中完成的工作、当前架构决策、已知问题与后续运行/测试方式。本文不包含真实 API key、token、密码或私钥内容。

## 0. 最新补充：macOS 本机设置 App 设计

本轮确认后续可以开发一个 macOS 原生 App，帮助用户在自己的 Mac 上完成 Claude Code 与 Codex 第三方模型本机代理设置。第一版只支持本机部署，不支持远程 SSH 部署。

### 0.1 当前决策

- App 形态：SwiftUI macOS App，包含设置向导、主状态页和菜单栏入口。
- 用户可输入：
  - Claude Anthropic-compatible Base URL、API Key、Opus/Sonnet/Haiku 对应模型名。
  - Codex OpenAI-compatible Base URL、API Key、多个 profile 的模型名和 reasoning effort。
- App 负责：
  - 安装或更新本机代理。
  - 生成并引导信任本机证书。
  - 写入并验证 LaunchAgent，确保 `RunAtLoad` 与 `KeepAlive`。
  - 配置 Claude Desktop/CLI 与 Codex App/CLI 的四类前缀 Base URL。
  - 编译并安装 `claude-ca-launcher`。
  - 显示 proxy、证书、LaunchAgent、Claude、Codex、dashboard 与 telemetry 状态。
- 安全边界：
  - 真实 API Key 只存 macOS Keychain。
  - Claude/Codex 配置、LaunchAgent plist、handoff、日志和 telemetry 不写真实 API Key。
  - 客户端配置需要 auth 字段时，只写非敏感本地占位 token。

### 0.2 新增/更新文件

- 中文设计文档：`docs/superpowers/specs/2026-05-14-macos-local-proxy-setup-app-design.md`。
- 实施任务卡：`docs/superpowers/plans/2026-05-14-macos-local-proxy-setup-app.md`。
- Git 忽略规则：`.gitignore`，用于忽略证书私钥、日志、telemetry、`.DS_Store` 和构建产物。
- 项目规则：`AGENTS.md`，补充项目文档默认使用简体中文，以及 macOS App spec 位置。

### 0.2.1 下一步执行建议

任务卡已经拆好。按计划应先执行 Task 1：让 Node 代理从 macOS Keychain 读取真实 provider API Key，再进入 SwiftUI App scaffold。原因是 App 的安全设计依赖“真实 key 只存在 Keychain，客户端配置只放本地非敏感 token”。

### 0.2.2 Task 1 完成记录：Node 代理读取 Keychain 上游 key

已在实现分支 `feature/macos-local-proxy-setup-app` 完成 Task 1：

- 新增 `claude-local-proxy/keychain.js`。
- 新增 `claude-local-proxy/tests/keychain.test.js`。
- 更新 `claude-local-proxy/server.js`：
  - Claude 透传请求不再转发客户端传入的 `Authorization`。
  - Codex bridge 不再转发客户端传入的 `Authorization`。
  - 代理优先从 macOS Keychain 读取真实 provider API Key。
  - Keychain 不存在对应 key 时，可回退到环境变量 `CLAUDE_UPSTREAM_API_KEY`、`CODEX_UPSTREAM_API_KEY`、`ANTHROPIC_AUTH_TOKEN`、`OPENAI_API_KEY` 或 `ARK_API_KEY`。

验证通过：

```bash
node --test claude-local-proxy/tests/keychain.test.js
node --test claude-local-proxy/tests/telemetry.test.js
node --check claude-local-proxy/server.js
node --check claude-local-proxy/telemetry.js
node --check claude-local-proxy/keychain.js
```

剩余风险：

- 尚未在真实 macOS Keychain 中写入 provider key 并做端到端请求验证；这会在 SwiftUI App 的 KeychainService 和安装流程完成后验证。

### 0.2.3 本机配置保护约束

CJ 明确要求：开发期间不能动本机正在运行的 Codex 配置。后续实现 macOS 设置 App 时必须遵守：

- 不修改真实 `~/.codex/config.toml`。
- 不修改真实 `~/.claude/settings.json`。
- 不修改真实 Claude Desktop config。
- 不写真实 `~/Library/LaunchAgents`。
- 不写真实 Keychain 生产项。
- 配置写入测试必须使用临时目录、fixture 或测试专用 Keychain service/account。
- 真正执行本机安装或写入生产配置前，必须由 CJ 单独明确确认。

### 0.2.4 Task 2 完成记录：SwiftUI App scaffold

已完成 Task 2，并使用 `Build macOS Apps` 插件建议的 SwiftPM/macOS GUI App 工作流：

- 新增 `macos/ProxySetupApp/Package.swift`。
- 新增 SwiftUI App 入口、`AppState`、`RootView`、`StatusDashboardView`。
- 新增菜单栏入口 `MenuBarExtra`。
- 新增 `script/build_and_run.sh`，用于构建 `.app` bundle 并启动/验证。
- 新增 `.codex/environments/environment.toml`，让 Codex App 可以使用项目 Run action。
- `script/build_and_run.sh --verify` 只启动当前 scaffold App，不写 Claude/Codex 配置。

验证通过：

```bash
cd macos/ProxySetupApp && swift build
cd macos/ProxySetupApp && swift test
./script/build_and_run.sh --verify
```

环境备注：

- 当前机器 `xcode-select` 指向 CommandLineTools，而不是完整 Xcode。
- CommandLineTools 没有 XCTest；Swift 测试改用 Swift Testing。
- 为了让 `swift test` 在当前 CLT 下找到 `Testing.framework` 和 `lib_TestingInterop.dylib`，`Package.swift` 的 test target 显式加入了 CLT Frameworks 和 usr/lib rpath。

### 0.2.5 Task 3 完成记录：配置模型与校验

已完成 Task 3，新增纯内存配置模型，不读写本机真实配置文件：

- 新增 `macos/ProxySetupApp/Sources/ProxySetupApp/Models/SetupConfiguration.swift`。
- 新增 `macos/ProxySetupApp/Tests/ProxySetupAppTests/SetupConfigurationTests.swift`。
- 配置模型覆盖：
  - Claude provider enable/base URL/keychain account。
  - Codex provider enable/base URL/keychain account。
  - Claude Opus/Sonnet/Haiku 模型映射。
  - Codex profiles。
  - 四类固定客户端前缀 Base URL。
- 校验覆盖：
  - provider Base URL 必须是 HTTPS。
  - 至少启用 Claude 或 Codex 其中一个 provider。
  - listen port 必须在 `1...65535`。

验证通过：

```bash
cd macos/ProxySetupApp && swift test --filter SetupConfigurationTests
cd macos/ProxySetupApp && swift build
```

### 0.2.6 Task 4 完成记录：KeychainService 与脱敏工具

已完成 Task 4：

- 新增 `macos/ProxySetupApp/Sources/ProxySetupApp/Services/KeychainService.swift`。
- 新增 `macos/ProxySetupApp/Sources/ProxySetupApp/Services/LogService.swift`。
- 新增 `macos/ProxySetupApp/Tests/ProxySetupAppTests/KeychainServiceTests.swift`。
- Keychain 测试使用测试专用 service：`CJLocalProxyTests`。
- 测试账号使用随机 UUID，并在 `defer` 中清理。
- 脱敏逻辑覆盖：
  - `Authorization: Bearer ...` -> `Authorization: Bearer <REDACTED>`。
  - API Key 显示只保留前 4 和后 4 位。

验证通过：

```bash
cd macos/ProxySetupApp && swift test --filter KeychainServiceTests
cd macos/ProxySetupApp && swift build
```

安全确认：

- 未写入生产 Keychain service/account。
- 未修改 `~/.codex/config.toml` 或其他本机真实客户端配置。

### 0.2.7 Task 5 完成记录：命令执行与环境检查

已完成 Task 5：

- 新增 `macos/ProxySetupApp/Sources/ProxySetupApp/Models/StatusModels.swift`。
- 新增 `macos/ProxySetupApp/Sources/ProxySetupApp/Services/CommandRunner.swift`。
- 新增 `macos/ProxySetupApp/Sources/ProxySetupApp/Services/PreflightService.swift`。
- 新增 `macos/ProxySetupApp/Tests/ProxySetupAppTests/PreflightServiceTests.swift`。
- `CommandRunner` 支持：
  - shell builtin `command -v <tool>` 的只读检测。
  - absolute executable。
  - 通过 `/usr/bin/env` 查找普通 executable。
- `PreflightService` 当前检测 `node`、`claude`、`codex` 三个命令。
- 测试使用 `MockCommandRunner`，不读取或写入本机真实配置。

验证通过：

```bash
cd macos/ProxySetupApp && swift test --filter PreflightServiceTests
cd macos/ProxySetupApp && swift build
```

安全确认：

- 未修改 `~/.codex/config.toml`。
- 未修改 `~/.claude/settings.json`。
- 未写 LaunchAgent。
- 未写生产 Keychain 项。

### 0.2.8 Task 6 完成记录：代理文件安装器

已完成 Task 6：

- 新增 `macos/ProxySetupApp/Sources/ProxySetupApp/Services/ProxyInstaller.swift`。
- 新增 `macos/ProxySetupApp/Tests/ProxySetupAppTests/ProxyInstallerTests.swift`。
- 新增 App 内置代理资源目录：
  - `macos/ProxySetupApp/Sources/ProxySetupApp/Resources/ProxyBundle/server.js`
  - `macos/ProxySetupApp/Sources/ProxySetupApp/Resources/ProxyBundle/telemetry.js`
  - `macos/ProxySetupApp/Sources/ProxySetupApp/Resources/ProxyBundle/keychain.js`
  - `macos/ProxySetupApp/Sources/ProxySetupApp/Resources/ProxyBundle/openssl-server.cnf`
  - `macos/ProxySetupApp/Sources/ProxySetupApp/Resources/ProxyBundle/bin/claude-ca-launcher.c`
- `keychain.js` 已纳入 bundle，因为 Task 1 后 `server.js` 依赖它。
- `ProxyInstaller` 当前能力：
  - 创建 app-managed 目录结构。
  - 将 bundled proxy 文件复制到安装目录。
  - 写入不含真实 API Key 的 `config/proxy.env`。

验证通过：

```bash
cd macos/ProxySetupApp && swift test --filter ProxyInstallerTests
cd macos/ProxySetupApp && swift build
cd macos/ProxySetupApp && swift test
node --check macos/ProxySetupApp/Sources/ProxySetupApp/Resources/ProxyBundle/server.js
node --check macos/ProxySetupApp/Sources/ProxySetupApp/Resources/ProxyBundle/telemetry.js
node --check macos/ProxySetupApp/Sources/ProxySetupApp/Resources/ProxyBundle/keychain.js
```

安全确认：

- 测试只写临时目录。
- 未修改 `~/Library/Application Support`。
- 未修改 `~/.codex/config.toml`。
- 未写真实 LaunchAgent 或生产 Keychain 项。

### 0.2.9 Task 7 完成记录：客户端配置生成

已完成 Task 7：

- 新增 `macos/ProxySetupApp/Sources/ProxySetupApp/Services/ClientConfigService.swift`。
- 新增 `macos/ProxySetupApp/Tests/ProxySetupAppTests/ClientConfigServiceTests.swift`。
- 支持生成：
  - Claude CLI `settings.json` 片段，base URL 指向 `/claude-cli`。
  - Claude Desktop gateway config，base URL 指向 `/claude-desktop`。
  - Codex App provider，base URL 指向 `/codex-app/v1`。
  - Codex CLI provider 和 profiles，base URL 指向 `/codex-cli/v1`。
- 客户端配置只写 `CJ_LOCAL_PROXY_TOKEN` 本地占位 token，不写真实 provider API Key。
- TOML 字符串支持 quote/backslash 转义。

验证通过：

```bash
cd macos/ProxySetupApp && swift test --filter ClientConfigServiceTests
cd macos/ProxySetupApp && swift build
cd macos/ProxySetupApp && swift test
```

安全确认：

- 只生成配置字符串。
- 未写 `~/.codex/config.toml`。
- 未写 `~/.claude/settings.json`。
- 未写 Claude Desktop config。

### 0.2.10 Task 8 完成记录：LaunchAgent plist 生成

已完成 Task 8：

- 新增 `macos/ProxySetupApp/Sources/ProxySetupApp/Services/LaunchAgentService.swift`。
- 新增 `macos/ProxySetupApp/Tests/ProxySetupAppTests/LaunchAgentServiceTests.swift`。
- 生成的 plist 包含：
  - `RunAtLoad = true`
  - `KeepAlive = true`
  - `ProgramArguments`
  - `WorkingDirectory`
  - stdout/stderr log path
  - proxy 环境变量
  - Keychain service/account 环境变量
- plist 不包含真实 API Key、`Bearer` 或 `sk-`。
- plist 字符串值做 XML escape。

验证通过：

```bash
cd macos/ProxySetupApp && swift test --filter LaunchAgentServiceTests
cd macos/ProxySetupApp && swift build
cd macos/ProxySetupApp && swift test
```

安全确认：

- 只生成 plist 字符串。
- 未写 `~/Library/LaunchAgents`。
- 未执行 `launchctl`。
- 未修改本机 Codex/Claude 配置。

### 0.2.11 Task 9 完成记录：证书服务

已完成 Task 9：

- 新增 `macos/ProxySetupApp/Sources/ProxySetupApp/Services/CertificateService.swift`。
- 新增 `macos/ProxySetupApp/Tests/ProxySetupAppTests/CertificateServiceTests.swift`。
- `CertificateService` 当前能力：
  - 生成 OpenSSL server config。
  - SAN 包含 `127.0.0.1`、`localhost`、`::1`。
  - 生成本机 CA/server cert 所需的 OpenSSL 命令数组。

验证通过：

```bash
cd macos/ProxySetupApp && swift test --filter CertificateServiceTests
cd macos/ProxySetupApp && swift build
cd macos/ProxySetupApp && swift test
```

安全确认：

- 只生成配置文本和命令数组。
- 未执行 OpenSSL。
- 未写系统 Keychain。
- 未信任证书。
- 未修改本机 Codex/Claude 配置。

### 0.2.12 Task 10 完成记录：验证与状态汇总

已完成 Task 10：

- 新增 `macos/ProxySetupApp/Sources/ProxySetupApp/Services/VerificationService.swift`。
- 新增 `macos/ProxySetupApp/Tests/ProxySetupAppTests/VerificationServiceTests.swift`。
- 当前能力：
  - 生成 `/health`、`/dashboard`、`/telemetry/summary` 和四类客户端前缀 health URL。
  - 表示验证状态：`notRun`、`passed`、`failed`。
  - 汇总 passed/failed 数量和整体是否通过。

验证通过：

```bash
cd macos/ProxySetupApp && swift test --filter VerificationServiceTests
cd macos/ProxySetupApp && swift build
cd macos/ProxySetupApp && swift test
```

安全确认：

- 未请求本机代理。
- 未启动或停止服务。
- 未修改本机 Codex/Claude 配置。

### 0.2.13 Task 11 完成记录：设置向导 UI

已完成 Task 11：

- 更新 `AppState`，加入内存态 `setupConfiguration` 和 sidebar selection。
- 更新 `RootView`，使用 macOS `NavigationSplitView`。
- 更新 `StatusDashboardView`，展示 Proxy、LaunchAgent、Certificate 状态占位与 dashboard/verification 操作。
- 新增：
  - `ProviderSettingsView`
  - `ModelMappingView`
  - `VerificationResultsView`
  - `SetupWizardView`
- 设置向导目前只编辑内存配置，尚未接入“应用配置到本机”的执行路径。

验证通过：

```bash
cd macos/ProxySetupApp && swift build
cd macos/ProxySetupApp && swift test
./script/build_and_run.sh --verify
```

安全确认：

- App 启动验证只打开 scaffold UI。
- 未写 `~/.codex/config.toml`。
- 未写 Claude 配置。
- 未写 LaunchAgent。
- 未写生产 Keychain 项。

### 0.2.14 Task 12 完成记录：集成验证、文档和 handoff

已完成 Task 12 文档收口：

- 新增 `macos/ProxySetupApp/README.md`。
- 更新 `docs/superpowers/specs/2026-05-14-macos-local-proxy-setup-app-design.md`：
  - 记录 Swift Testing / CommandLineTools 测试环境约束。
  - 记录开发期间不得修改本机真实 Codex/Claude 配置、LaunchAgent 或生产 Keychain 项。
- 本 handoff 持续记录每个任务完成状态。

最终全量验证命令见本轮最终回复。

### 0.2.15 Task 8-12 复核与 UI 易用性增强

本轮按 CJ 要求继续执行 Task 8、Task 9、Task 10、Task 11、Task 12，并重点改善 UI 易用性、中文/英文并列和“本机部署但不误伤当前配置”的安全边界。

新增/增强：

- `SetupConfiguration` 新增 provider 兼容类型：
  - `Anthropic 兼容 / Anthropic-compatible`
  - `OpenAI 兼容 / OpenAI-compatible`
- `AppState` 新增：
  - Claude/Codex API Key 输入态。
  - 配置校验状态。
  - Keychain 保存状态。
  - 设置向导 tab 状态。
  - 准备状态 checklist。
- `ProviderSettingsView` 改为更完整的设置页：
  - 用户可输入 Base URL、API Key、Keychain account。
  - 用户可选择 Anthropic/OpenAI 兼容类型。
  - “保存 Key / Save Keys” 只写 macOS Keychain，并在保存后清空明文输入框。
- `ModelMappingView` 增强：
  - Claude Opus/Sonnet/Haiku 映射更清楚。
  - Codex profiles 支持新增、删除。
  - reasoning effort 改为 segmented picker。
- `StatusDashboardView` 增强：
  - 展示 Proxy、LaunchAgent、Certificate 三个核心状态。
  - 展示四类客户端分流路径：Claude Desktop、Claude CLI、Codex App、Codex CLI。
  - 展示准备状态 checklist。
- `VerificationResultsView` 增强：
  - 展示 health、dashboard、telemetry summary、四类客户端 health URL。
  - 展示 LaunchAgent `bootstrap/kickstart/print` 与证书信任命令预览。
  - 展示 Claude CLI、Claude Desktop gateway、Codex TOML 配置预览。
- `LaunchAgentService` 增强：
  - 除 plist 外，生成 `launchctl bootstrap`、`kickstart`、`print`、`bootout` 命令数组。
- `CertificateService` 增强：
  - 生成 login keychain 信任 CA 的 `security add-trusted-cert` 命令数组。
- `VerificationService` 增强：
  - 生成带名称的 pending verification summary，明确区分 desktop/cli/app/cli。
- `macos/ProxySetupApp/README.md` 与设计 spec 已更新为中文说明。

安全确认：

- 本轮自动化执行没有修改真实 `~/.codex/config.toml`。
- 没有修改真实 `~/.claude/settings.json`。
- 没有修改 Claude Desktop config。
- 没有写 `~/Library/LaunchAgents`。
- 没有写生产 Keychain 项。
- Keychain 单元测试仍只使用测试专用 `CJLocalProxyTests` service/account。

### 0.2.16 Task 13 完成记录：本机安装编排与安全预览

本轮继续执行下一个任务，完成 Task 13：把前面分散的安装、证书、LaunchAgent 和验证服务串成可审计的本机安装编排层，但仍不做真实一键安装。

新增/更新文件：

- 新增 `macos/ProxySetupApp/Sources/ProxySetupApp/Services/LocalInstallationService.swift`。
- 新增 `macos/ProxySetupApp/Tests/ProxySetupAppTests/LocalInstallationServiceTests.swift`。
- 更新 `macos/ProxySetupApp/Sources/ProxySetupApp/Views/VerificationResultsView.swift`。
- 更新 `docs/superpowers/plans/2026-05-14-macos-local-proxy-setup-app.md`，追加 Task 13。
- 更新 `docs/superpowers/specs/2026-05-14-macos-local-proxy-setup-app-design.md`。
- 更新 `macos/ProxySetupApp/README.md`。
- 本 handoff 持续记录任务状态。

当前能力：

- `LocalInstallationService.buildPlan` 可生成本机安装计划，包含：
  - 配置校验。
  - 复制代理文件。
  - 写入 `config/proxy.env`。
  - 准备 `openssl-server.cnf`。
  - 写入 LaunchAgent plist。
  - 准备 `launchctl bootstrap/kickstart/print` 命令数组。
  - 准备证书信任命令数组。
  - 准备 health、dashboard、telemetry 和四类客户端 health 验证端点。
- `LocalInstallationService.prepareLocalFiles` 支持注入临时 `InstallationEnvironment`，只在传入的 `installRoot` 与 `launchAgentDirectory` 下写文件。
- 设置向导验证页展示安装计划与安全边界。
- 配置无效时，验证页展示错误原因，不再静默显示空列表。

安全确认：

- 未修改本机真实 `~/.codex/config.toml`。
- 未修改真实 `~/.claude/settings.json`。
- 未修改 Claude Desktop config。
- 未写真实 `~/Library/LaunchAgents`。
- 未写生产 Keychain 项。
- 未执行真实 `launchctl`、`security add-trusted-cert` 或 `openssl`。
- 自动化测试只写临时目录。
- 生成的 `proxy.env` 与 plist 不包含真实 provider API Key、`Bearer ` 或 `sk-`。

验证通过：

```bash
cd macos/ProxySetupApp && swift test --filter LocalInstallationServiceTests
```

最终全量验证命令见本轮最终回复。

### 0.2.17 Task 14 完成记录：安装确认、备份、回滚与 dry-run diff

本轮完成 Task 14：在真实安装按钮接入之前，新增 dry-run、备份 manifest、回滚和确认门禁层。该任务仍不做真实安装，不修改本机正在运行的 Codex/Claude 配置。

新增/更新文件：

- 新增 `macos/ProxySetupApp/Sources/ProxySetupApp/Services/InstallationSafetyService.swift`。
- 新增 `macos/ProxySetupApp/Tests/ProxySetupAppTests/InstallationSafetyServiceTests.swift`。
- 更新 `macos/ProxySetupApp/Sources/ProxySetupApp/Services/LocalInstallationService.swift`：
  - 新增 `managedFileChanges`，生成 proxy runtime、OpenSSL config、LaunchAgent plist 三类 managed changes。
- 更新 `macos/ProxySetupApp/Sources/ProxySetupApp/Services/ClientConfigService.swift`：
  - 新增 `ClientConfigEnvironment`。
  - 新增 `managedClientConfigChanges`，用注入路径生成 Claude CLI、Claude Desktop gateway、Codex config 三类 managed changes。
- 更新 `macos/ProxySetupApp/Sources/ProxySetupApp/Services/ProxyInstaller.swift`：
  - 新增 `renderRuntimeConfig`，供写入和 dry-run 共用。
- 更新 `macos/ProxySetupApp/Sources/ProxySetupApp/AppState.swift`：
  - 新增 Keychain 写入确认状态。
  - 未确认账号、未确认 Keychain 写入或未输入 `KEYCHAIN` 时，状态层拒绝保存 provider key。
- 更新 `macos/ProxySetupApp/Sources/ProxySetupApp/Views/SetupWizardView.swift`：
  - “保存 Key / Save Keys” 旁新增 Keychain 写入确认栏。
  - 确认条件未满足时按钮禁用。
- 更新 `macos/ProxySetupApp/Sources/ProxySetupApp/Views/VerificationResultsView.swift`：
  - 展示 dry-run diff。
  - 展示 create/update/unchanged 状态。
  - 展示 execution gate 确认要求。
- 更新 `docs/superpowers/plans/2026-05-14-macos-local-proxy-setup-app.md`，追加 Task 14。
- 更新 `docs/superpowers/specs/2026-05-14-macos-local-proxy-setup-app-design.md`。
- 更新 `macos/ProxySetupApp/README.md`。

当前能力：

- `InstallationSafetyService.dryRun`：
  - 对 managed files 生成 `create`、`update`、`unchanged`。
  - 只读现有文件，不写目标文件。
  - preview 会脱敏 `Bearer ...` 与 `sk-...` 形态的敏感值。
- `InstallationSafetyService.createBackups`：
  - 只备份已存在文件。
  - 为不存在的目标记录 `existed = false`。
  - 生成 manifest，不把 proposed contents 写进 manifest。
- `InstallationSafetyService.rollback`：
  - 只按 manifest 回滚。
  - 只允许操作调用方显式传入的 allowed target roots 内的目标。
  - 原本存在的文件从 backup 恢复。
  - 原本不存在但被安装创建的文件会被删除。
  - 缺 backup 时失败，不静默跳过。
- `InstallationConfirmation`：
  - 必须确认已查看 dry-run。
  - 必须确认已创建 backups。
  - 必须确认理解系统变更。
  - 必须输入 `INSTALL` 才允许继续。
- `KeychainWriteConfirmation`：
  - 必须确认已核对账号。
  - 必须确认理解会写入 macOS Keychain。
  - 必须输入 `KEYCHAIN` 才允许保存 provider key。

安全确认：

- 未修改本机真实 `~/.codex/config.toml`。
- 未修改真实 `~/.claude/settings.json`。
- 未修改 Claude Desktop config。
- 未写真实 `~/Library/LaunchAgents`。
- 未写生产 Keychain 项。
- 保存 provider key 的 UI 和状态层都新增确认门禁，自动化测试覆盖未确认不允许保存。
- 未执行真实 `launchctl`、`security add-trusted-cert` 或 `openssl`。
- dry-run UI 只读目标文件，不写入。
- 备份/回滚测试只写临时目录。
- manifest 不包含 proposed config contents，不包含真实 API Key。

验证通过：

```bash
cd macos/ProxySetupApp && swift test
cd macos/ProxySetupApp && swift build
node --test claude-local-proxy/tests/telemetry.test.js claude-local-proxy/tests/keychain.test.js
node --check claude-local-proxy/server.js
node --check claude-local-proxy/telemetry.js
node --check claude-local-proxy/keychain.js
git diff --check
rg -n "sk-|Bearer |Authorization: Bearer" handoff.md docs macos/ProxySetupApp claude-local-proxy || true
./script/build_and_run.sh --verify
```

说明：敏感串扫描命中的是代码、测试和文档中的脱敏模式、占位示例或断言，没有发现真实 API Key、token、SSH 密码或私钥内容。

### 0.2.18 测试机 App 包生成记录

本轮按 CJ 要求，在当前开发机生成可拿到测试机验证的 macOS App 测试包。该包是本地测试包，不是正式 notarized 发行包。

生成信息：

- 源码提交：`42ee911 feat: add macos install safety layer`。
- App bundle：`dist/ProxySetupApp.app`。
- 测试包：`dist/ProxySetupApp-T14-42ee911-20260516.zip`。
- zip 大小：约 `483K`。
- SHA256：`a7d646f6e75961d8e92b5b46e3bfcd7cbc5dacb488a218dc8a92c18cdd794363`。

执行过的验证：

```bash
./script/build_and_run.sh --verify
codesign --force --deep --sign - dist/ProxySetupApp.app
codesign --verify --deep --strict --verbose=2 dist/ProxySetupApp.app
ditto -c -k --keepParent dist/ProxySetupApp.app dist/ProxySetupApp-T14-42ee911-20260516.zip
ditto -x -k dist/ProxySetupApp-T14-42ee911-20260516.zip /tmp/proxysetupapp-package-check
codesign --verify --deep --strict --verbose=2 /tmp/proxysetupapp-package-check/ProxySetupApp.app
```

测试机打开方式：

```bash
ditto -x -k ProxySetupApp-T14-42ee911-20260516.zip .
xattr -dr com.apple.quarantine ProxySetupApp.app
open ProxySetupApp.app
```

注意事项：

- 该包只做 ad-hoc 签名，未 notarize；测试机如出现 Gatekeeper 提示，需要手动允许打开。
- 当前 App 仍是安全预览阶段，不自动执行 `launchctl`、`security add-trusted-cert` 或 `openssl`。
- 当前 App 不自动写真实 Claude/Codex 配置或真实 `~/Library/LaunchAgents`。

### 0.3 Git 状态

- 主仓库目录：`/Users/chjia/Coding/CC-CodexThirdPModels`。
- Task 14 开发 worktree：`/Users/chjia/Coding/CC-CodexThirdPModels/.worktrees/macos-install-safety`。
- Task 14 实现分支：`feature/macos-install-safety`。
- Remote：`git@github.com:MoraCJ/CC-CodexThirdPModels.git`。
- `main` 已推送到 `origin/main`，当前远端最新提交为 `42ee911`。
- `dist/` 构建产物被 `.gitignore` 忽略，不提交测试 zip。

## 0A. 最新补充：Usage Dashboard 与客户端来源区分

本轮在远端 Mac `172.16.66.188` 的统一代理上新增了脱敏 telemetry 与一页 dashboard，用于观察 Claude Code 与 Codex 分别使用了哪些模型、请求量、token usage、失败数与耗时。

### 0.1 当前最新结论

- 远端实际代理已更新：`/Users/corptest/Documents/Codex/claude-code-app-api/claude-local-proxy/server.js`。
- 新增 helper：`/Users/corptest/Documents/Codex/claude-code-app-api/claude-local-proxy/telemetry.js`。
- Dashboard：`https://127.0.0.1:38443/dashboard`。
- JSON summary：`https://127.0.0.1:38443/telemetry/summary`。
- JSON recent events：`https://127.0.0.1:38443/telemetry/events`。
- Telemetry 文件：`/Users/corptest/Documents/Codex/claude-code-app-api/claude-local-proxy/logs/telemetry.jsonl`。
- Telemetry 不记录 API key、Authorization、Cookie、prompt、response 正文，只记录模型、客户端、状态码、耗时和 token usage 等结构化指标。

### 0.2 四类客户端来源

代理通过 URL 前缀强识别客户端来源，剥离前缀后再走原有上游转发逻辑：

| 客户端 | Base URL | Telemetry client |
| --- | --- | --- |
| Claude Code Desktop | `https://127.0.0.1:38443/claude-desktop` | `claude_desktop` |
| Claude Code CLI | `https://127.0.0.1:38443/claude-cli` | `claude_cli` |
| Codex App | `https://127.0.0.1:38443/codex-app/v1` | `codex_app` |
| Codex CLI | `https://127.0.0.1:38443/codex-cli/v1` | `codex_cli` |

无前缀旧路径仍兼容，但只会标为 `claude_unknown` 或 `codex_unknown`，不建议长期使用。

### 0.3 远端配置变更

- Claude Desktop 3P config：`inferenceGatewayBaseUrl` 已改为 `https://127.0.0.1:38443/claude-desktop`。
- Claude CLI settings：`~/.claude/settings.json` 中 `ANTHROPIC_BASE_URL` 已改为 `https://127.0.0.1:38443/claude-cli`。
- Codex App 默认 provider：`ark-coding-app`，base URL 为 `https://127.0.0.1:38443/codex-app/v1`。
- Codex CLI profiles：`ark-doubao`、`ark-kimi`、`ark-glm` 已改为 provider `ark-coding-cli`，base URL 为 `https://127.0.0.1:38443/codex-cli/v1`。
- Claude Desktop Code host 的 `claude` 软链仍指向 `claude-local-proxy/bin/claude-ca-launcher`；launcher 已重新编译，会额外注入 `ANTHROPIC_BASE_URL=https://127.0.0.1:38443/claude-desktop`。

### 0.4 自动启动状态

远端代理由 LaunchAgent 托管：

```text
~/Library/LaunchAgents/com.cj.claude-local-https-proxy.plist
```

已验证：

```text
state = running
properties = keepalive | runatload | inferred program
```

因此该服务会在用户登录后自动加载，并由 `KeepAlive` 保持运行。后续排查时不要只看端口是否存在，也要看 `launchctl print gui/$(id -u)/com.cj.claude-local-https-proxy`。

### 0.5 本轮备份与验证

- 代理文件备份：`server.js.bak.telemetry.20260514185654`。
- Dashboard UI 备份：`server.js.bak.dashboard-ui.20260514191848`。
- 客户端配置备份后缀：`.bak.client-sources.20260514110134`。
- 本地测试通过：
  - `node --test claude-local-proxy/tests/telemetry.test.js`：4 passed。
  - `node --check claude-local-proxy/server.js`：通过。
  - `node --check claude-local-proxy/telemetry.js`：通过。
- 远端验证通过：
  - `curl -sk https://127.0.0.1:38443/health` 返回 `codexUpstream`、`telemetryFile`、`dashboard`、`clientPrefixes`。
  - `curl -sk https://127.0.0.1:38443/dashboard` 返回 dashboard HTML。
  - Dashboard 已调整为更清晰的运维看板样式，英文标签旁提供中文，例如 `Proxy Usage Dashboard / 代理用量看板`、`Requests / 请求`、`Recent Requests / 最近请求`。
  - `curl -sk https://127.0.0.1:38443/telemetry/summary` 返回 JSON summary。
  - `/claude-desktop/health`、`/claude-cli/health`、`/codex-app/health`、`/codex-cli/health` 均返回 ok。

### 0.6 本轮新增/更新的项目文件

- `claude-local-proxy/server.js`
- `claude-local-proxy/telemetry.js`
- `claude-local-proxy/tests/telemetry.test.js`
- `claude-local-proxy/bin/claude-ca-launcher.c`
- `claude-local-proxy/README.md`
- `tools/update_remote_proxy_client_sources.js`
- `docs/superpowers/plans/2026-05-14-proxy-usage-dashboard.md`
- `AGENTS.md`
- `handoff.md`

## 0B. 历史补充：Claude + Codex 统一代理

本轮在远端 Mac `172.16.66.188` 上继续完成了 Codex 接入与代理合并。旧版本文主要记录 Claude Code Desktop 第三方 API 接入；当前最新状态是 Claude 与 Codex 共用一个本机 HTTPS 代理入口。

### 0.1 当前最新结论

- 已把 Codex 代理逻辑合进 Claude 本机代理：`/Users/corptest/Documents/Codex/claude-code-app-api/claude-local-proxy/server.js`。
- 统一入口为 `https://127.0.0.1:38443`，由 LaunchAgent `com.cj.claude-local-https-proxy` 托管。
- Claude 仍走 Anthropic-compatible 路径，转发到 `https://ark.cn-beijing.volces.com/api/coding`。
- Codex 走 OpenAI Responses API 入口 `/v1/responses`，由本机代理转换为 Chat Completions，再转发到 `https://ark.cn-beijing.volces.com/api/coding/v3/chat/completions`。
- 旧 Codex 独立代理端口 `38444` 已停止监听；旧文件和 LaunchAgent 保留为回滚参考。
- 文档、PPT、runbook 均不保存真实 API key、SSH 密码或私钥。

### 0.2 模型策略

Claude 继续使用槽位名，由代理映射真实模型：

```text
claude-opus-4-6   -> glm-5.1
claude-sonnet-4-6 -> kimi-k2.6
claude-haiku-4-5  -> doubao-seed-2.0-pro
```

Codex 直接使用真实模型名，不再仿照 Claude 做槽位映射：

```text
ark-doubao -> doubao-seed-2.0-pro
ark-kimi   -> kimi-k2.6
ark-glm    -> glm-5.1
```

Codex 配置位于远端 Mac 的 `~/.codex/config.toml`，核心配置为 provider `ark-coding`，`base_url = "https://127.0.0.1:38443/v1"`，`wire_api = "responses"`。常用切换命令：

```bash
codex -p ark-doubao
codex -p ark-kimi
codex -p ark-glm
```

### 0.3 已验证信号

- `lsof` 显示 `127.0.0.1:38443` 正在监听。
- `127.0.0.1:38444` 不再监听。
- `curl -sk https://127.0.0.1:38443/health` 返回 Claude upstream、Codex upstream 与模型映射。
- Claude `/v1/messages` 返回 200，代理日志可见 Claude 槽位模型映射。
- Codex 默认模型 `doubao-seed-2.0-pro` 可正常回复。
- Codex profiles `ark-doubao`、`ark-kimi`、`ark-glm` 均可正常回复。
- Codex tool call 测试通过。

### 0.4 新增交付物

- `docs/claude-codex-unified-proxy-runbook.md`
- `docs/claude-codex-unified-proxy-runbook.docx`
- `docs/claude-codex-unified-proxy-intro.pptx`
- `docs/rendered-unified-proxy-runbook/`
- `outputs/claude-codex-unified-proxy-deck/rendered/`
- `tools/build_claude_codex_unified_proxy_docs.py`
- `tools/build_claude_codex_unified_proxy_deck.cjs`

### 0.5 仍需注意

- 本地材料目录中的 `claude-local-proxy/server.js` 仍可能是旧 Claude-only 版本；远端 Mac 上的 `server.js` 才是当前已验证的合并版。
- 下一步建议把远端合并后的 `server.js` 同步回本地材料仓库，再补最小 smoke test。
- 回滚时优先使用远端已有备份：`server.js.bak.codex-merge.20260514144040`、`~/.codex/config.toml.bak.unified.20260514145435`、`~/.codex/config.toml.bak.real-profiles.20260514150226`。

### 0.6 统一代理标准材料

本轮新增了一套统一代理标准交付物，统一阐述如何通过本机 HTTPS 代理配置 Claude Code 与 Codex 使用第三方模型：

- `docs/unified-proxy-third-party-models-intro.pptx`
  - 介绍 PPT，13 页。
  - 面向讲解与汇报，覆盖统一代理优势、目标架构、HTTPS/证书、代理能力、模型策略、Claude 配置、Codex 配置、Codex App 模型切换、验证效果、运维、安全与标准化交付。
- `docs/unified-proxy-third-party-models-technical-manual.docx`
  - 标准技术手册 Word，7 页。
  - 面向维护者，覆盖目的、架构、组件、路由、模型策略、代理配置、Claude Code 配置、Codex 配置、Codex CLI/App 模型切换、验证、故障处理、回滚和安全边界。
- `docs/unified-proxy-third-party-models-ai-runbook.md`
  - 面向其他 AI 工具的执行 runbook。
  - 使用 `<HOST>`、`<USER>`、`<PROJECT_ROOT>`、`<ARK_API_KEY>` 等占位符，强调备份、禁止泄露敏感值、配置步骤、Codex App 模型切换、验证标准、故障决策树与回滚。
- `docs/unified-proxy-third-party-models-technical-manual.md`
  - 技术手册的 Markdown 源内容，便于后续 diff 和再生成。
- `docs/rendered-unified-third-party-models-manual/`
  - Word 渲染 QA 产物，含 PDF、页面 PNG 和 contact sheet。
- `outputs/unified-third-party-models-deck/rendered/`
  - PPT 渲染 QA 产物，含 PDF、页面 PNG 和 contact sheet。
- `tools/build_unified_third_party_model_materials.py`
  - 生成合并版 Word 技术手册、技术手册 Markdown、AI runbook。
- `tools/build_unified_third_party_model_deck.cjs`
  - 生成合并版介绍 PPT。

已完成验证：

- Word 通过 LibreOffice 渲染为 7 页 PNG/PDF。
- PPT 通过 LibreOffice 渲染为 13 页 PNG/PDF。
- 生成材料已扫描敏感串，未发现真实 API key 或 SSH 密码片段。

## 1. 当前已经完成了什么

- 排查并解决 Claude Code Desktop 新版本配置第三方 API 时，CLI 可用但 App 不稳定的问题。
- 明确成功方案不是让 Desktop 直接指向 Ark，而是使用本机 HTTPS 代理：
  - Desktop 3P Gateway 指向 `https://127.0.0.1:38443`。
  - 本机代理转发到 Ark Anthropic-compatible endpoint：`https://ark.cn-beijing.volces.com/api/coding`。
  - macOS Keychain 信任本机自签 CA，解决 Electron 网络栈和 Cowork/host loop 的证书信任问题。
- 实现并验证本机 HTTPS 代理：
  - 支持 `/health` 健康检查。
  - 透传请求头，不在代理代码中保存 API key。
  - 按 Claude 槽位模型名重写真实上游模型名。
- 完成最终模型槽位映射：
  - `claude-opus-4-6` -> `glm-5.1`
  - `claude-sonnet-4-6` -> `kimi-k2.6`
  - `claude-haiku-4-5` -> `doubao-seed-2.0-pro`
- 对齐 Claude Code CLI / Desktop Code host 配置：
  - `~/.claude/settings.json` 走本机代理。
  - 删除会强制覆盖模型选择的 `ANTHROPIC_MODEL`。
  - 删除旧 `modelOverrides`，避免与代理映射重复或冲突。
  - `ANTHROPIC_DEFAULT_*_MODEL` 使用 Claude 槽位名，而不是真实上游模型名。
- 处理 Desktop Code host binary 下载失败问题：
  - Desktop 日志里以 `[CCD] Initialized with version ...` 为准确定版本目录。
  - 本次远端 Mac 实际使用 `2.1.138`，需要创建 `.verified` 防止 App 反复 repair/download。
  - 当 `downloads.claude.ai` 下载超时，可把 Desktop 期望路径软链到本机可用 CLI 或证书 launcher。
- 定位并处理 Cowork 证书失败：
  - 现象包括 `server is busy`、证书认证失败。
  - 日志真实错误是 `SSL certificate verification failed`。
  - 最终通过 `claude-ca-launcher` 强制注入 `NODE_USE_SYSTEM_CA`、`NODE_EXTRA_CA_CERTS`、`SSL_CERT_FILE` 后，Code/Cowork 调用链都能访问本机 HTTPS 代理。
- 在远端 Mac `172.16.66.188` 上完成配置验证：
  - 本机代理健康检查通过。
  - 系统证书信任后，普通 `curl https://127.0.0.1:38443/health` 成功。
  - Claude Desktop 3P 日志出现 `ConfigHealth recomputed { state: 'healthy', provider: 'gateway' }`。
  - 代理日志出现 `/v1/models`、`/v1/messages`、`/v1/messages/count_tokens` 返回 200。
- 生成并更新可分享材料：
  - Markdown 版 Runbook。
  - Word 版 Runbook，已渲染为 7 页 PNG/PDF 做版式检查。
  - 介绍用 PPT，9 页，偏分享讲解，包含实现逻辑示意图；PPT 布局检查 0 errors / 0 warnings。

## 2. 修改了哪些文件

### 项目内文件

- `claude-local-proxy/server.js`
  - 本机 HTTPS 代理服务。
  - 实现请求转发、模型映射、健康检查。
- `claude-local-proxy/README.md`
  - 记录代理用途、监听地址、上游地址、模型映射。
- `claude-local-proxy/openssl-server.cnf`
  - 自签 server certificate 的 SAN 配置。
- `claude-local-proxy/certs/`
  - 本机代理证书相关文件。
  - 包含 `ca.crt`、`server.crt`、`server.key` 等。
  - 注意：`*.key` 是私钥，不应公开分享或提交到公共仓库。
- `claude-local-proxy/logs/`
  - 代理运行日志。
  - 公开分享前应检查是否含敏感请求头、token 或个人路径。
- `docs/claude-code-desktop-third-party-api-runbook.md`
  - 详细成功经验 Runbook。
- `docs/claude-code-desktop-third-party-api-runbook.docx`
  - Word 版 Runbook。
- `docs/rendered-runbook/`
  - Word 渲染 QA 产物，包括 PDF 和页面 PNG。
- `tools/build_claude_desktop_3p_runbook.py`
  - 生成 Markdown / Word Runbook 的脚本。
- `docs/claude-code-desktop-third-party-api-intro.pptx`
  - 分享介绍用 PPT。
- `outputs/`
  - PPT 生成工作区，保留 slide source、preview、layout、manifest 等可追溯材料。
- `handoff.md`
  - 本交接文档。

### 本机或远端 Mac 上的项目外配置

- `~/Library/LaunchAgents/com.cj.claude-local-https-proxy.plist`
  - 用 LaunchAgent 自动启动本机 HTTPS 代理。
- `~/Library/Application Support/Claude-3p/configLibrary/_meta.json`
  - Claude Desktop 3P 配置库入口。
- `~/Library/Application Support/Claude-3p/configLibrary/<uuid>.json`
  - 当前 Desktop 3P Gateway 配置。
- `~/Library/Application Support/Claude-3p/claude_desktop_config.json`
  - Desktop 3P 部署模式配置。
- `~/.claude/settings.json`
  - Claude Code CLI / host binary 配置。
- `~/.claude/settings.json.bak.*`
  - 修改 CLI settings 前创建的备份。
- `~/Library/Application Support/Claude-3p/claude-code/<version>/.verified`
  - 防止 Desktop 把手工准备的 host binary 目录当作未完成下载而清空。
- `~/Library/Application Support/Claude-3p/claude-code/<version>/claude.app/Contents/MacOS/claude`
  - Desktop Code host binary 期望路径；可软链到本机 CLI 或 `claude-ca-launcher`。
- `~/Library/Application Support/Claude-3p/claude-code/<version>/claude`
  - 部分 host loop 路径会直接调用的同级 binary；同样建议软链到 `claude-ca-launcher`。
- `/path/to/claude-local-proxy/bin/claude-ca-launcher`
  - Cowork/host loop 证书环境兜底 launcher。
- macOS System 或 login Keychain
  - 加入并信任本地 CA，用于 Desktop/Electron/host loop 访问本机 HTTPS 代理。

## 3. 还有哪些待办

- 如果要把这个目录变成正式 Git 项目：
  - 增加 `.gitignore`，避免提交 `certs/*.key`、运行日志、个人路径和临时渲染产物。
  - 当前目录未检测到 `.git`，无法确认“项目集成分支”的 Git 状态。
- 把代理启动、证书生成、Keychain 信任、Desktop 3P 配置、host binary 兜底写成一键安装脚本。
- 把远端配置动作拆成可复用脚本：
  - `install_local_proxy.sh`
  - `configure_claude_3p.sh`
  - `install_claude_code_host_launcher.sh`
- 继续观察 Cowork：
  - 当前 API 调用链可用，但 bash/VM 能力依赖 `downloads.claude.ai` 资源下载。
  - 如果公司网络无法连通该域名，需要配置系统代理、网络白名单或离线缓存。
- 在 Claude Desktop / Claude Code CLI 升级后重新验证：
  - Desktop 内置 Code host binary 版本可能变化。
  - `~/Library/Application Support/Claude-3p/claude-code/<version>` 里的版本号要按日志更新。
- 迁移到另一台 Mac 时，需要重新生成或重新信任本地证书；不要直接复用私钥。

## 4. 当前架构决策

- 使用本机 HTTPS 代理作为唯一兼容层。
  - Desktop 3P、Desktop Code host、CLI 都统一指向 `https://127.0.0.1:38443`。
  - 代理再转发到 Ark Anthropic-compatible endpoint。
- 使用 HTTPS 而不是 HTTP。
  - Claude Code Desktop 新版本要求本地代理为 HTTPS。
  - Electron 网络栈和 host loop 需要可信证书链，因此本机 CA 必须加入 macOS Keychain 并设置 SSL trust。
- 模型显示名与真实上游模型解耦。
  - App / CLI 侧保留 Claude 槽位名：Opus、Sonnet、Haiku。
  - 代理侧负责将槽位映射到真实模型。
  - 避免在 CLI settings 中使用 `ANTHROPIC_MODEL` 直接强制覆盖模型。
- API key 不写死在代理代码中。
  - 代理只透传请求头。
  - Desktop / CLI 配置负责提供 token。
- 用 LaunchAgent 托管本机代理。
  - 保证登录后自动启动。
  - 避免每次手动运行 Node 代理。
- Desktop host binary 使用版本目录兜底。
  - 操作前必须先关闭 Claude 和 Claude Helper。
  - 创建 `.verified` 后再放置 host binary 或 launcher。
  - 对 Cowork 优先使用 `claude-ca-launcher`，不要只依赖 CLI settings 里的环境变量。

## 5. 已知问题

- 当前目录不是 Git worktree：
  - `git status` 返回 `fatal: not a git repository`。
  - 因此无法确认或切换“项目集成分支”。
- 自签 CA 是本机状态：
  - 迁移到其他电脑必须重新生成或重新信任证书。
  - 不建议把私钥复制到其他机器。
- 远程 SSH 下无法完成所有系统证书信任动作：
  - `security add-trusted-cert -d -r trustRoot -p ssl -k /Library/Keychains/System.keychain ...` 可能报 `The authorization was denied since no user interaction was possible.`
  - 需要用户在目标 Mac 本机交互式执行 sudo，或由 MDM/配置描述文件下发证书。
- Desktop/CLI 升级可能影响配置：
  - Claude Desktop 可能改变内置 Code host binary 版本目录。
  - Claude Code CLI 新版本可能改变 settings 字段行为。
- 代理模型映射当前基于模型名字符串包含关系：
  - 包含 `opus` -> 大模型。
  - 包含 `sonnet` 或 `claude` -> 中模型。
  - 包含 `haiku` -> 小模型。
  - 如果未来模型槽位命名规则改变，需要检查映射逻辑。
- Desktop `/v1/models` discovery 可能显示 `0 usable models`：
  - 只要 Desktop 配置中显式设置 `inferenceModels`，且 health 状态为 healthy，该现象可以不作为阻断项。
- Cowork 的 bash/VM 能力与模型 API 是两条问题线：
  - API 日志 200 说明模型调用链路可用。
  - `[HostLoop] VM boot failed; bash proxy unavailable` 通常是 `downloads.claude.ai` 下载超时或 VM 资源缺失导致。
- `docs/rendered-runbook/` 是 QA 产物：
  - 有助于检查 Word 版式，但不是运行代理所必需。

## 6. 下一步建议

1. 先把项目纳入 Git 管理，或确认真正的集成分支所在目录。
2. 增加 `.gitignore`：
   - 忽略 `claude-local-proxy/certs/*.key`
   - 忽略 `claude-local-proxy/logs/*.log`
   - 视情况忽略 `docs/rendered-runbook/` 和 `outputs/**/previews/`
3. 做一键安装脚本，按 macOS 阶段拆分：
   - 生成证书。
   - 写 LaunchAgent。
   - 写 Desktop 3P config。
   - 写 CLI settings。
   - 安装 host binary/launcher。
   - 输出 `/health`、Keychain、Desktop log、proxy log 检查结果。
4. 在公司网络环境下为 `downloads.claude.ai` 做单独连通性验证：
   - 可直连则让 Desktop 自动下载 VM/rootfs/host binary。
   - 不可直连则配置系统代理或准备离线缓存方案。
5. 把 `claude-ca-launcher` 编译纳入脚本，并让 host binary 两个入口都指向 launcher。
6. 每次 Claude Desktop 或 CLI 更新后，按“运行/测试”章节重新验证。

## 7. 如何运行/测试当前项目

### 7.1 启动本机代理

优先使用 LaunchAgent：

```bash
launchctl print gui/$(id -u)/com.cj.claude-local-https-proxy
launchctl kickstart -k gui/$(id -u)/com.cj.claude-local-https-proxy
```

如果只想手动运行代理，可在项目目录中执行类似命令：

```bash
cd /Users/chjia/Documents/Codex/2026-05-11/claude-code-app-api/claude-local-proxy

LISTEN_HOST=127.0.0.1 \
LISTEN_PORT=38443 \
UPSTREAM_BASE_URL=https://ark.cn-beijing.volces.com/api/coding \
BIG_MODEL=glm-5.1 \
MIDDLE_MODEL=kimi-k2.6 \
SMALL_MODEL=doubao-seed-2.0-pro \
TLS_CERT_FILE="$PWD/certs/server.crt" \
TLS_KEY_FILE="$PWD/certs/server.key" \
node server.js
```

### 7.2 检查端口与健康状态

```bash
lsof -nP -iTCP:38443 -sTCP:LISTEN

curl --silent --show-error \
  --cacert /Users/chjia/Documents/Codex/2026-05-11/claude-code-app-api/claude-local-proxy/certs/ca.crt \
  https://127.0.0.1:38443/health
```

期望 `/health` 返回类似：

```json
{
  "ok": true,
  "upstream": "https://ark.cn-beijing.volces.com/api/coding",
  "bigModel": "glm-5.1",
  "middleModel": "kimi-k2.6",
  "smallModel": "doubao-seed-2.0-pro"
}
```

### 7.3 检查证书信任

```bash
security verify-cert \
  -c /Users/chjia/Documents/Codex/2026-05-11/claude-code-app-api/claude-local-proxy/certs/server.crt \
  -p ssl \
  -s 127.0.0.1
```

目标 Mac 上如果普通 `curl https://127.0.0.1:38443/health` 不带 `--cacert` 也能成功，说明系统信任链已经足够。

### 7.4 检查 Desktop 3P 日志

```bash
tail -n 200 "$HOME/Library/Logs/Claude-3p/main.log"
```

关键成功信号：

```text
ConfigHealth recomputed { state: 'healthy', provider: 'gateway' }
```

可以忽略但要理解的日志：

```text
Gateway /v1/models returned 0 usable models { rawCount: ... }
Auto-update error
```

前者在显式配置 `inferenceModels` 时不一定阻断，后者和第三方 API 调用无关。

### 7.5 检查代理请求日志

```bash
tail -n 160 /Users/chjia/Documents/Codex/2026-05-11/claude-code-app-api/claude-local-proxy/logs/proxy.log
```

期望看到类似：

```text
request model claude-sonnet-4-6
mapped model claude-sonnet-4-6 -> kimi-k2.6
POST /v1/messages?beta=true -> 200
POST /v1/messages/count_tokens?beta=true -> 200
```

三种槽位都应可验证：

```text
claude-opus-4-6   -> glm-5.1
claude-sonnet-4-6 -> kimi-k2.6
claude-haiku-4-5  -> doubao-seed-2.0-pro
```

### 7.6 检查 CLI settings

```bash
node -e '
const fs=require("fs");
const p=process.env.HOME+"/.claude/settings.json";
const j=JSON.parse(fs.readFileSync(p,"utf8"));
console.log(JSON.stringify(j.env || {}, null, 2));
'
```

重点：

```text
ANTHROPIC_BASE_URL=https://127.0.0.1:38443
ANTHROPIC_AUTH_TOKEN=<ARK_API_KEY>
ANTHROPIC_DEFAULT_OPUS_MODEL=claude-opus-4-6
ANTHROPIC_DEFAULT_SONNET_MODEL=claude-sonnet-4-6
ANTHROPIC_DEFAULT_HAIKU_MODEL=claude-haiku-4-5
NODE_USE_SYSTEM_CA=1
NODE_EXTRA_CA_CERTS=/path/to/claude-local-proxy/certs/ca.crt
```

不应存在：

```text
ANTHROPIC_MODEL
modelOverrides
```

### 7.7 检查 Desktop Code host binary / launcher

先从日志确定版本：

```bash
grep -E "\\[CCD\\] Initialized with version" "$HOME/Library/Logs/Claude-3p/main.log" | tail
```

再检查对应目录：

```bash
VERSION=2.1.138
BASE="$HOME/Library/Application Support/Claude-3p/claude-code/$VERSION"

ls -la "$BASE/.verified"
ls -la "$BASE/claude.app/Contents/MacOS/claude"
ls -la "$BASE/claude"
"$BASE/claude.app/Contents/MacOS/claude" --version
```

如果 Cowork 报证书失败，优先确认这些路径是否指向 `claude-ca-launcher`，以及 launcher 是否能在极简环境下访问本机代理：

```bash
env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin" \
  "$BASE/claude.app/Contents/MacOS/claude" \
  -p '只回复 ok'
```

### 7.8 重新生成文档

```bash
cd /Users/chjia/Documents/Codex/2026-05-11/claude-code-app-api
/Users/chjia/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 \
  tools/build_claude_desktop_3p_runbook.py
```

输出：

```text
docs/claude-code-desktop-third-party-api-runbook.md
docs/claude-code-desktop-third-party-api-runbook.docx
```
