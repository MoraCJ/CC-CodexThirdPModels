# Claude Code Desktop 第三方 API 接入 Handoff

更新时间：2026-05-19

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

## 0.2.30 测试机只读排查记录：T20 后 Claude Desktop 仍不可用

### 检查范围

2026-05-19 通过 SSH 只读检查测试机 `172.16.66.187`，用户 `nh`。本次没有修改远端程序、配置、LaunchAgent、Keychain 或 Claude/Codex 文件。

### 关键证据

- `ProxySetupApp` 当前运行的是 T20 包，二进制中已包含：
  - `Claude Desktop Host / Desktop 运行组件`
  - `Initialize Desktop Host`
  - `ANTHROPIC_AUTH_TOKEN=CJ_LOCAL_PROXY_TOKEN`
- 本机代理正常：
  - LaunchAgent `com.cj.claude-local-https-proxy` 为 `state = running`。
  - 程序为 `/usr/local/bin/node`。
  - `RunAtLoad` 与 `KeepAlive` 生效。
  - `https://127.0.0.1:38443/health` 与 `/claude-desktop/health` 返回 `ok`。
- Claude Desktop 已进入 3P 模式：
  - 进程使用 `--user-data-dir=/Users/nh/Library/Application Support/Claude-3p`。
  - `_meta.json.appliedId` 指向 UUID 配置。
  - `inferenceGatewayBaseUrl` 指向 `https://127.0.0.1:38443/claude-desktop`。
- 当前失败不是代理不可用：
  - telemetry 只有 `claude_cli` 成功请求，没有 `claude_desktop` 生成请求。
  - Claude Desktop 在进入模型请求前就卡在 host 初始化。
- `~/Library/Application Support/Claude-3p/claude-code` 仍为空。
- Desktop 日志反复出现：
  - `[CCD] Binary preflight: no binary on disk — attempting repair download`
  - `Downloading bundle from https://downloads.claude.ai/claude-code-releases/2.1.138/darwin-arm64/claude.app.tar.zst`
  - `Request error: net::ERR_CONNECTION_TIMED_OUT`
  - `No path to Claude code executable`
  - `Host Claude Code binary not available. Check that the download completed.`
- Cowork VM 还额外缺资源：
  - `cowork_vm_node.log` 显示 `rootfs.img missing`。
  - VM 尝试下载 `https://downloads.claude.ai/vms/linux/arm64/.../rootfs.img.zst` 并超时。

### 当前判断

T20 的方向是对的，但真实测试机仍没有可用 Desktop Host，原因需要拆成两层：

1. Code/Desktop host 层：版本目录 `claude-code/2.1.138` 没有 `.verified`、`claude.app/Contents/MacOS/claude` 或同级 `claude`。这说明 T20 的 host 初始化没有实际落到版本目录，或曾写入后被 Desktop repair/download 流程清掉。当前 App 没有持久化 host 初始化日志，无法从远端只读证据确认是哪一种。
2. Cowork/VM 层：即使 host binary 补齐，Cowork 仍可能因为 `rootfs.img` 缺失而失败。测试机无法访问 `downloads.claude.ai`，所以仅创建 host launcher 不足以让 Cowork 完整工作；需要支持 VM/rootfs 离线初始化或在 UI 中明确标记 Cowork 仍缺离线资源。

### 下一步建议

- 先不要继续盲目改代理；代理健康和 CLI 请求已证明本机 HTTPS 代理链路正常。
- App 需要新增持久化安装/Host 初始化日志，记录：
  - 解析到的 Desktop host version。
  - 是否创建版本目录。
  - `.verified` 写入路径。
  - 两个 symlink 写入结果。
  - 初始化后复查结果。
- Host 初始化流程需要改为更强约束：
  - 如果 Claude Desktop 已解析出 version 但 host 仍缺失，安装页应把 `Initialize Host` 作为明确待办，而不是让用户误以为 `Install & Start` 已完成所有 Desktop 修复。
  - 初始化后立即检查 `claude-code/<version>`，若仍为空，界面必须红色提示。
- Cowork 支持需要单独任务卡：
  - 探测 `vm_bundles/claudevm.bundle`、`claude-code-vm/<version>` 和 rootfs。
  - 支持离线导入或从可用机器复制 VM/rootfs 资源。
  - UI 区分 `Code Host ready` 与 `Cowork VM ready`。

## 0.2.29 T20 完成记录：Claude Desktop Host 离线初始化

### 背景与根因

2026-05-19 在测试机 `172.16.66.187` 排查发现：

- Claude Desktop 已经进入 `deploymentMode: 3p`，进程使用 `~/Library/Application Support/Claude-3p`。
- 本机代理、LaunchAgent、`/claude-cli` 和 `/claude-desktop/health` 均正常。
- Claude Code CLI 可以通过本机代理工作。
- Claude Desktop Cowork 和 Code 对话失败，UI 显示 `Host Claude Code binary not available. Check that the download completed.`。
- `~/Library/Logs/Claude-3p/main.log` 中持续出现 `downloads.claude.ai` 超时，Desktop 无法下载：
  - `claude-code-releases/2.1.138/darwin-arm64/claude.app.tar.zst`
  - `claude-code-releases/2.1.138/linux-arm64/claude.zst`
  - VM rootfs 资源
- `~/Library/Application Support/Claude-3p/claude-code` 为空。

结论：这不是 `npm` 或 `brew` 导致的目录问题。Claude Desktop 不复用 Homebrew/npm 安装的 `claude` CLI；它维护自己的 Desktop host bundle。测试机网络无法访问 `downloads.claude.ai`，所以 Desktop host binary 没有初始化完成。

### 本轮实现

- 新增 `SetupConfiguration.claudeDesktopSupportDirectoryName`，默认 `Claude-3p`。
  - 该字段用于 Desktop 3P data root 名称。
  - 校验不能为空，不能包含 `/` 或 `:`。
- 新增 `ClaudeDesktopEnvironment`，统一派生 Desktop 相关路径：
  - `~/Library/Application Support/<name>/configLibrary`
  - `~/Library/Application Support/<name>/claude_desktop_config.json`
  - `~/Library/Application Support/<name>/claude-code`
  - `~/Library/Application Support/<name>/claude-code-vm`
  - `~/Library/Application Support/<name>/vm_bundles/claudevm.bundle`
  - `~/Library/Logs/<name>/main.log`
- `ClientConfigEnvironment.defaultEnvironment(...)` 改为跟随 Desktop data root 名称派生配置路径，避免 `Claude-3p` 散落硬编码。
- 新增 `ClaudeDesktopHostBundleService`：
  - 从 Desktop `main.log` 解析 host version，支持 `[CCD] Initialized with version ...` 和 `claude-code-releases/<version>/...`。
  - 检查 `.verified`、`claude.app/Contents/MacOS/claude`、同级 `claude`、VM version directory、VM bundle。
  - 在无法联网下载官方 bundle 时，可用本机 `claude` CLI 生成 `claude-ca-launcher` 脚本，注入本地 CA、`/claude-desktop` Base URL 和本机占位 token。
  - 将 Desktop 期望的两个 host binary 入口软链到 `claude-ca-launcher`。
  - 写入 `.verified`，避免 Desktop repair/download 清理目录。
- 启动配置页新增 `Claude Desktop Host / Desktop 运行组件` 面板：
  - 可查看/修改 Desktop data root 名称，默认 `Claude-3p`。
  - 支持 `检查 Host / Check Host`。
  - 支持 `初始化 Host / Initialize Host`。
  - 展示 host 检查项、初始化进度和命令记录。
- 安装流在写入代理文件后自动检查 Desktop Host；如果已解析到 version 且 binary 缺失，会自动尝试离线初始化。
- 状态页新增 Desktop Host 状态卡。
- 日志页新增 Desktop Host 日志读取入口，读取 `~/Library/Logs/<name>/main.log`。
- `LogService.redact` 增强脱敏规则，覆盖 Authorization、x-api-key、api_key、ANTHROPIC_AUTH_TOKEN、Cookie、Set-Cookie、`sk-*`。

### 安全边界

- 没有把 Claude 官方 host bundle 放入仓库或 App 资源。
- 离线初始化只生成本 App 的 launcher、软链和 `.verified`。
- 不记录真实 API Key、Authorization、Cookie、prompt 或 response。
- 单元测试全部注入临时 `ClaudeDesktopEnvironment`，不写本机真实 `~/Library/Application Support/Claude-3p`。

### 验证

```bash
cd macos/ProxySetupApp && swift build
cd macos/ProxySetupApp && swift test
node --check claude-local-proxy/server.js
node --check claude-local-proxy/telemetry.js
node --check claude-local-proxy/keychain.js
./script/build_and_run.sh --verify
codesign --verify --deep --strict --verbose=2 dist/ProxySetupApp.app
codesign --verify --deep --strict --verbose=2 /tmp/proxysetupapp-t20-package-check/ProxySetupApp.app
```

交付包：

- `dist/ProxySetupApp-T20-DesktopHostInit-20260519.zip`
- SHA256：`5c29c339216ee05b6c908bfa869082a61bf5bc70c551fcb02e54e983a4e80187`

剩余风险：

- 本机验证已覆盖构建、单元测试、App 启动、JS 语法检查和签名校验；仍需在测试机上用真实 Claude Desktop 验证 Desktop Host 初始化后 Cowork/Code 是否恢复响应。
- 如果 Claude Desktop 后续升级改变 host bundle 协议或 data root 规则，需要重新用 `检查 Host / Check Host` 确认版本目录和日志格式。

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

### 0.2.19 测试机反馈修复：字体、按钮反馈与提示可见性

本轮根据测试机截图反馈，完成一次 UX polish。目标是解决“字体偏小、按键反馈弱、提示不明显”的问题，不改变安装安全边界。

源码提交：

- `e762700 feat: polish macos setup feedback`

改进内容：

- 放大侧栏、面板标题、说明文字、输入框、按钮和验证页 monospaced 内容。
- 设置向导顶部新增两张明显状态卡：
  - 配置检查状态。
  - Keychain 保存状态。
- `检查配置 / Check` 后不再只改底部小字，而是在状态卡和右上角 badge 同步显示结果。
- `保存 Key / Save Keys` 不可点击时，底部直接显示原因：
  - 未输入 API Key。
  - 未勾选账号确认。
  - 未确认写入 Keychain。
  - 未输入大写 `KEYCHAIN`。
- Keychain 确认区改成独立提示条，并把输入框 placeholder 改成 `输入大写 KEYCHAIN / Type KEYCHAIN`。
- 保存成功后继续清空 API Key 输入框，但顶部 Keychain 状态卡会显示已保存。

安全确认：

- 没有新增真实安装执行路径。
- 没有自动写 Claude/Codex 配置、LaunchAgent 或证书信任。
- 没有修改 Keychain 写入门禁；仍需两个确认框和大写 `KEYCHAIN`。

验证与打包：

```bash
cd macos/ProxySetupApp && swift test
cd macos/ProxySetupApp && swift build
./script/build_and_run.sh --verify
codesign --force --deep --sign - dist/ProxySetupApp.app
codesign --verify --deep --strict --verbose=2 dist/ProxySetupApp.app
ditto -c -k --keepParent dist/ProxySetupApp.app dist/ProxySetupApp-UX-e762700-20260518.zip
ditto -x -k dist/ProxySetupApp-UX-e762700-20260518.zip /tmp/proxysetupapp-ux-package-check
codesign --verify --deep --strict --verbose=2 /tmp/proxysetupapp-ux-package-check/ProxySetupApp.app
```

新测试包：

- `dist/ProxySetupApp-UX-e762700-20260518.zip`
- zip 大小：约 `525K`。
- SHA256：`d7e48973c38f25ccb9a472a4ee8751cfa0a5a3ceb53c6b6fd8bcc816a3c1fbab`。

### 0.2.20 测试机反馈修复：Keychain 保存失败信息与覆盖逻辑

测试机反馈：点击 `保存 Key / Save Keys` 后出现 `ProxySetupApp.KeychainService.KeychainError error 0`，无法判断真实原因。

根因判断：

- `error 0` 是 Swift enum bridge 到 `NSError` 后的泛化 code，不是真实 Keychain OSStatus。
- 旧逻辑保存前会先 `SecItemDelete`，再 `SecItemAdd`。测试机如果曾用旧测试包保存过同名 Keychain 条目，新包 ad-hoc 签名不同，删除或覆盖旧条目可能被 Keychain 拒绝。

修复内容：

- `KeychainService.save` 改为：
  - 先 `SecItemAdd`。
  - 如遇 `errSecDuplicateItem`，再 `SecItemUpdate`。
  - 不再先删除旧值，降低权限/签名变化导致的失败风险。
- `KeychainError` 改为 `LocalizedError`：
  - 显示 `SecCopyErrorMessageString`。
  - 显示真实 `OSStatus`。
  - 对 auth/interaction/entitlement 类错误，提示测试机可先删除旧 `CJLocalProxy` 条目后重试。
- 新增测试：
  - 重复保存同一 account 会覆盖为新值。
  - Keychain 错误信息包含底层 OSStatus。

验证与打包：

```bash
cd macos/ProxySetupApp && swift test --filter KeychainServiceTests
cd macos/ProxySetupApp && swift test
cd macos/ProxySetupApp && swift build
./script/build_and_run.sh --verify
codesign --force --deep --sign - dist/ProxySetupApp.app
codesign --verify --deep --strict --verbose=2 dist/ProxySetupApp.app
ditto -c -k --keepParent dist/ProxySetupApp.app dist/ProxySetupApp-Keychain-bb0db7d-20260518.zip
ditto -x -k dist/ProxySetupApp-Keychain-bb0db7d-20260518.zip /tmp/proxysetupapp-keychain-package-check
codesign --verify --deep --strict --verbose=2 /tmp/proxysetupapp-keychain-package-check/ProxySetupApp.app
```

新测试包：

- `dist/ProxySetupApp-Keychain-bb0db7d-20260518.zip`
- zip 大小：约 `526K`。
- SHA256：`59060ab3124d8c2df72c0f3ec300fef9dbf58de2748ad2791c958ee91a2001cc`。

如果测试机仍因旧包留下的 Keychain ACL 失败，可先在测试机执行：

```bash
security delete-generic-password -s CJLocalProxy -a claude-upstream-api-key
security delete-generic-password -s CJLocalProxy -a codex-upstream-api-key
```

再重新打开 App 保存。删除的是测试机 `CJLocalProxy` service 下这两个 provider API Key 条目，不影响其他 Keychain 项。

### 0.2.21 测试机反馈修复：保存 Key 右侧提示增强

测试机反馈：`保存 Key / Save Keys` 按钮右侧提示仍然不够醒目。

修复内容：

- 将按钮右侧提示从灰色小字改为状态胶囊。
- 使用更粗的 `headline` 字重。
- 根据状态切换颜色：
  - 已保存或可保存：绿色。
  - 已输入 key 但确认不足：橙色。
  - 未输入 key：蓝色。
- 胶囊带图标、浅色背景和描边，避免被底部按钮栏压住。

验证与打包：

```bash
cd macos/ProxySetupApp && swift test
cd macos/ProxySetupApp && swift build
./script/build_and_run.sh --verify
codesign --force --deep --sign - dist/ProxySetupApp.app
codesign --verify --deep --strict --verbose=2 dist/ProxySetupApp.app
ditto -c -k --keepParent dist/ProxySetupApp.app dist/ProxySetupApp-SaveHint-ab56606-20260518.zip
ditto -x -k dist/ProxySetupApp-SaveHint-ab56606-20260518.zip /tmp/proxysetupapp-savehint-package-check
codesign --verify --deep --strict --verbose=2 /tmp/proxysetupapp-savehint-package-check/ProxySetupApp.app
```

新测试包：

- `dist/ProxySetupApp-SaveHint-ab56606-20260518.zip`
- zip 大小：约 `533K`。
- SHA256：`3cc769981d737c205bae146a853b5061bcceba43de46b1f372f6ca5c398e1404`。

### 0.2.22 Task 15 完成记录：真实安装执行、可用性 UI 与 AppIcon

本轮继续执行下一张任务卡，让 macOS App 从“配置预览”进入“用户显式确认后可真实安装”的状态。

实现内容：

- 新增 `InstallationExecutionService`：
  - 安装前校验配置，并要求 `InstallationConfirmation` 全部通过且输入大写 `INSTALL`。
  - 先为所有 managed files 创建 backup manifest。
  - 复制内置代理资源，写入 `proxy.env`、OpenSSL config 和 LaunchAgent plist。
  - 写入 Claude CLI、Claude Desktop 3P、Codex config。
  - 缺证书时执行 OpenSSL 生成命令。
  - 执行 `security add-trusted-cert` 信任本机 CA。
  - 执行 `launchctl bootout/bootstrap/kickstart/print`。
  - 执行 `/health`、`/dashboard`、`/telemetry/summary` 和四类客户端 health 验证。
- 新增 `InstallationExecutionServiceTests`：
  - 全部使用临时目录、注入环境和 mock command runner。
  - 覆盖安装成功、缺少确认门禁、必需命令失败中断。
  - 验证 manifest 不包含真实 key 形态。
- `AppState` 接入安装执行状态：
  - 安装中/安装完成/安装失败提示。
  - 命令执行记录。
  - 备份 manifest 路径。
  - 端点验证结果。
- `VerificationResultsView`：
  - `执行门禁 / Execution Gate` 升级为 `执行安装 / Install & Start`。
  - 只有配置检查通过、三个确认项勾选、输入 `INSTALL` 后安装按钮启用。
  - 安装后展示命令日志、备份 manifest 和 health 验证结果。
- Claude Desktop 配置路径修正：
  - 从临时 `~/Library/Application Support/Claude-3p/config.json` 改为项目 runbook 要求的 `configLibrary` 体系。
  - 当时写入 `~/Library/Application Support/Claude-3p/configLibrary/cj-local-proxy.json`。
  - 当时写入 `~/Library/Application Support/Claude-3p/configLibrary/_meta.json`，`appliedId` 指向 `cj-local-proxy`。
  - 注意：Claude Desktop 1.7196+ 已在 T19 修正为 UUID configLibrary 文件与新字段 schema。
  - 写入 `~/Library/Application Support/Claude-3p/claude_desktop_config.json`，启用 `deploymentMode: 3p`。
- Codex 模型配置说明与切换：
  - 顶层默认 `model` 使用第一个 profile。
  - 模型页显示“当前 Codex 默认模型”。
  - 非默认 profile 提供 `设为默认 / Make Default` 按钮。
  - 其他 profile 仍写入 `config.toml`，用于手工 profile 切换。
- UI 可用性修复：
  - 放大 `Setup Step` 三段切换控件。
  - `检查配置 / Check` 使用与 `保存 Key / Save Keys` 一致的 prominent 按钮样式。
  - Check 状态色：未检查蓝色、通过绿色、失败橙色。
  - 配置检查提示卡与 Keychain 已保存提示卡统一最小高度。
- AppIcon：
  - 使用 CJ 提供的“哇！通过啦！”图片生成 `AppIcon.icns`。
  - 打包脚本写入 `CFBundleIconFile=AppIcon`。
  - `.app` 内包含 `Contents/Resources/AppIcon.icns`。
- 打包脚本修复：
  - `Package.swift` 改为 `.copy("Resources/ProxyBundle")`，保留 `ProxyBundle` 目录结构。
  - `script/build_and_run.sh` 复制 SwiftPM resource bundle 到 `Contents/Resources`。
  - `ProxyInstaller` 优先从 `Bundle.main.resourceURL/ProxySetupApp_ProxySetupApp.bundle/ProxyBundle` 找代理资源，开发测试时 fallback 到 SwiftPM `Bundle.module`。
  - 修复了资源 bundle 放在 `.app` 根目录导致 `codesign --strict` 报 `unsealed contents` 的问题。

验证通过：

```bash
cd macos/ProxySetupApp && swift test
cd macos/ProxySetupApp && swift build
./script/build_and_run.sh --verify
node --check claude-local-proxy/server.js
node --check claude-local-proxy/telemetry.js
node --check claude-local-proxy/keychain.js
codesign --force --deep --sign - dist/ProxySetupApp.app
codesign --verify --deep --strict --verbose=2 dist/ProxySetupApp.app
ditto -c -k --keepParent dist/ProxySetupApp.app dist/ProxySetupApp-T15-InstallUI-20260518.zip
ditto -x -k dist/ProxySetupApp-T15-InstallUI-20260518.zip /tmp/proxysetupapp-t15-package-check
codesign --verify --deep --strict --verbose=2 /tmp/proxysetupapp-t15-package-check/ProxySetupApp.app
```

新测试包：

- `dist/ProxySetupApp-T15-InstallUI-20260518.zip`
- zip 大小：约 `2.4M`。
- SHA256：`fe3e25bb63df0667e8f68666f1fd623f11c3e5be9cc620b256cb98d46beb62d2`。

安全备注：

- 本轮自动化测试没有写本机真实 `~/.codex/config.toml`、`~/.claude/settings.json`、Claude Desktop config、真实 LaunchAgent 或生产 Keychain。
- 真实安装只能由用户在 App 内完成检查与 `INSTALL` 门禁后手动触发。

### 0.2.23 测试机反馈修复：安装后验证 HTTP 000

测试机反馈：安装执行记录里 LaunchAgent bootstrap/kickstart/print 成功，但验证端点全部显示 `失败 / HTTP 000`，界面状态为 `Installed, but verification needs attention`。

判断：

- `launchctl print` 成功只能说明 LaunchAgent job 已加载，不代表 Node 代理已经完成启动并开始监听端口。
- `HTTP 000` 是 curl 没拿到 HTTP 状态，常见原因是启动窗口期连接被拒绝或连接超时。
- 截图里的 `Stop existing LaunchAgent` 红字是首次安装时正常信号：旧 job 不存在，`bootout` 返回 `Boot-out failed`，安装流程会忽略这个非关键失败。

修复内容：

- `VerificationService.run` 增加验证重试：
  - 默认每个端点最多 8 次。
  - 每次间隔 0.5 秒。
  - 测试可注入 `attempts` 和 `retryDelayNanoseconds`。
- curl 参数改为：

```bash
curl -skS --connect-timeout 2 --max-time 5 -o /dev/null -w "%{http_code}" <url>
```

这样保留 `-k` 跳过本机自签证书校验，同时 `-S` 会把连接错误写入 stderr，界面能显示更具体原因。

- `AppState` 新增 `recheckInstallation()`：
  - 只重新跑 health/dashboard/telemetry/client health 验证。
  - 不重装、不写配置、不重新生成证书、不动 Keychain。
- `VerificationResultsView`：
  - 验证端点卡片新增 `重新验证 / Recheck`。
  - 执行安装卡片新增 `重新验证 / Recheck`。
  - `验证通过 / Verification passed` 使用绿色状态。

验证通过：

```bash
cd macos/ProxySetupApp && swift test
cd macos/ProxySetupApp && swift build
node --check claude-local-proxy/server.js
node --check claude-local-proxy/telemetry.js
node --check claude-local-proxy/keychain.js
./script/build_and_run.sh --verify
codesign --force --deep --sign - dist/ProxySetupApp.app
codesign --verify --deep --strict --verbose=2 dist/ProxySetupApp.app
ditto -c -k --keepParent dist/ProxySetupApp.app dist/ProxySetupApp-T16-VerifyRetry-20260518.zip
ditto -x -k dist/ProxySetupApp-T16-VerifyRetry-20260518.zip /tmp/proxysetupapp-t16-package-check
codesign --verify --deep --strict --verbose=2 /tmp/proxysetupapp-t16-package-check/ProxySetupApp.app
```

新测试包：

- `dist/ProxySetupApp-T16-VerifyRetry-20260518.zip`
- zip 大小：约 `2.5M`。
- SHA256：`f0399dd64ddb4d0b4e43a7df47907086ed7a61fe71bffe236e04542a6d2003f2`。

测试机操作建议：

- 如果旧包已安装并已显示 dashboard 可打开，说明代理大概率已起来。
- 等 5-10 秒后可点新版 App 里的 `重新验证 / Recheck`。
- 仍失败时再看 `~/Library/Application Support/CJLocalProxy/claude-local-proxy/logs/proxy.err.log`。

### 0.2.24 Task 17 完成记录：启动配置入口与还原原厂服务

本轮根据测试机体验反馈继续改 macOS App：把启动相关操作放到左侧菜单里的独立页面，并新增一键还原 Claude/Codex 官方服务的能力。

实现内容：

- 左侧菜单新增 `启动配置 / Start`：
  - `AppState.selectedSection` 默认改为 `.start`，App 打开后优先看到启动配置页。
  - 页面集中展示 `检查配置 / Check`、`重新验证 / Recheck`、`打开 Dashboard / Open Dashboard`、准备状态、安装启动和还原原厂服务。
  - 验证页的安装控件改为复用同一套 `InstallStartControlsView`，避免两处逻辑漂移。
- 新增 `FactoryRestoreService`：
  - 还原前要求 `FactoryRestoreConfirmation` 通过：确认备份、确认回到官方服务、输入大写 `RESTORE`。
  - 为 6 个目标创建 backup manifest：Claude CLI settings、Claude Desktop gateway、Claude Desktop meta、Claude Desktop deployment mode、Codex config、LaunchAgent plist。
  - 执行 `launchctl bootout` 停止本机代理 LaunchAgent。
  - 删除本 App 管理的 Claude Desktop gateway 文件。
  - 从 Claude Desktop `_meta.json` 中移除 `cj-local-proxy` 与对应 `appliedId`。
  - 从 Claude Desktop `claude_desktop_config.json` 中移除 `deploymentMode: 3p`，保留其它用户字段。
  - 从 Claude CLI `settings.json` 中移除本 App 写入的代理 env key，保留用户其它 env/key。
  - 从 Codex `config.toml` 中移除 `ark-coding-app`、`ark-coding-cli` provider、本 App 生成的 profiles 和本 App 写入的顶层默认模型配置，保留用户其它 profile/section。
  - 删除 `~/Library/LaunchAgents/com.cj.claude-local-https-proxy.plist`。
  - 不删除 Keychain 中的真实 API Key，避免误删密钥。
- `AppState`：
  - 新增还原状态、还原命令记录、还原备份 manifest 路径。
  - 新增 `restoreFactoryDefaults()`，还原成功后把 proxy status 标记为 `已还原官方服务 / Official defaults restored`。
- 新增 `StartupConfigurationView` 与 `StartupActionsView`：
  - 启动页把安装与还原作为两个主操作卡片。
  - 还原卡片明确说明“只移除本 App 管理的代理配置，Keychain API Key 保留”。
- 测试：
  - 新增 `FactoryRestoreServiceTests`，全部使用临时目录和 mock runner。
  - 覆盖只移除 managed config、不破坏用户配置、创建 backup manifest、缺确认拒绝执行。
  - `SmokeTests` 覆盖侧边栏启动入口、AppState 还原门禁与注入 executor。
- 文档：
  - 更新 `macos/ProxySetupApp/README.md`。
  - 更新 `docs/superpowers/plans/2026-05-14-macos-local-proxy-setup-app.md`，新增 Task 17。

验证通过：

```bash
cd macos/ProxySetupApp && swift test
cd macos/ProxySetupApp && swift build
node --check claude-local-proxy/server.js
node --check claude-local-proxy/telemetry.js
node --check claude-local-proxy/keychain.js
./script/build_and_run.sh --verify
codesign --force --deep --sign - dist/ProxySetupApp.app
codesign --verify --deep --strict --verbose=2 dist/ProxySetupApp.app
ditto -c -k --keepParent dist/ProxySetupApp.app dist/ProxySetupApp-T17-StartRestore-20260519.zip
ditto -x -k dist/ProxySetupApp-T17-StartRestore-20260519.zip /tmp/proxysetupapp-t17-package-check
codesign --verify --deep --strict --verbose=2 /tmp/proxysetupapp-t17-package-check/ProxySetupApp.app
```

新测试包：

- `dist/ProxySetupApp-T17-StartRestore-20260519.zip`
- zip 大小：约 `2.5M`。
- SHA256：`fa76e45cf4c7e68c0854e5108b3581d71dc99f5f8d222aac77d6d21cf8c15c4b`。

安全备注：

- 本轮自动化测试没有写本机真实 `~/.codex/config.toml`、`~/.claude/settings.json`、Claude Desktop config、真实 LaunchAgent 或生产 Keychain。
- 真实安装仍必须由用户在 App 内完成检查和 `INSTALL` 门禁后手动触发。
- 真实还原必须由用户在 App 内完成备份确认、官方服务确认和 `RESTORE` 门禁后手动触发。
- 还原原厂服务不会删除 Keychain 中保存的真实 API Key。

### 0.2.25 用户操作手册

本轮新增面向测试机和新电脑的中文操作手册：

- 新增 `docs/proxy-setup-app-user-manual.md`。
- 更新 `macos/ProxySetupApp/README.md`，指向操作手册。

手册覆盖：

- 获取并打开 `ProxySetupApp-T17-StartRestore-20260519.zip`。
- 首次打开 App 后的左侧菜单说明。
- Provider、Base URL、API Key、Keychain service/account 的填写方式。
- `KEYCHAIN`、`INSTALL`、`RESTORE` 三个确认词的用途。
- macOS Keychain 弹窗应输入当前 Mac 登录密码。
- Claude 模型映射与 Codex 默认模型/profile 的使用方式。
- 安装启动、重新验证、Dashboard 检查、LaunchAgent 检查。
- 一键还原原厂服务的效果与边界。
- 常见问题：保存 Key 不可点、Keychain 授权、HTTP 000、客户端未走代理、重新配置服务商。

验证：

```bash
git diff --check
```

### 0.2.26 测试机安装卡住排查记录：Node 路径写死

测试机：`172.16.66.187`，用户：`nh`。

现象：

- 用户点击 `执行安装 / Install & Start` 后，界面长时间停留在 `正在安装并启动代理 / Installing and starting proxy...`。
- App 缺少实时步骤进度与命令日志，用户无法知道卡在哪一步。

只读排查结果：

- `ProxySetupApp` 仍在运行。
- 子进程停在：

```text
launchctl kickstart -k gui/501/com.cj.claude-local-https-proxy
```

- LaunchAgent 状态：

```text
state = spawn scheduled
last exit code = 78: EX_CONFIG
properties = keepalive | runatload | penalty box | inferred program
```

- `curl -skS --connect-timeout 2 --max-time 5 https://127.0.0.1:38443/health` 连接失败。
- `proxy.log` 与 `proxy.err.log` 均为 0 字节，说明代理进程未进入 Node 脚本阶段。
- LaunchAgent plist 使用：

```text
/opt/homebrew/bin/node
```

- 测试机实际 Node 路径：

```text
/usr/local/bin/node
v24.15.0
```

- 测试机不存在：

```text
/opt/homebrew/bin/node
/usr/bin/node
```

根因：

- 当前 App 默认把 LaunchAgent 的 Node 路径固定为 `/opt/homebrew/bin/node`。
- 在 Intel/Homebrew 或其它安装方式的 Mac 上，Node 可能位于 `/usr/local/bin/node` 或其它路径。
- LaunchAgent 无法执行不存在的 Node，导致 `EX_CONFIG`，`kickstart` 长时间等待，UI 一直显示安装中。

已确认的问题：

1. 外部依赖路径不能写死：
   - `node`
   - `npm`
   - `brew`
   - 后续如需 `openssl`、`git`、`curl`，也应先探测真实路径。
2. `检查配置 / Check` 当前没有把外部依赖探测纳入 preflight。
3. `安装并启动 / Install & Start` 当前缺少实时进度和命令日志，只在整个流程结束后回填结果。
4. 外部命令执行缺少明确 timeout；`launchctl kickstart` 这类命令卡住时，用户只能强退 App。
5. health 验证当前 7 个 endpoint 串行重试，失败场景最坏可达数分钟，且 UI 未显示正在验证哪个 endpoint。

后续修复要求：

- 在 App 内实现依赖探测，优先顺序建议：
  - `which node`，候选 `/opt/homebrew/bin/node`、`/usr/local/bin/node`。
  - `which npm`，候选 `/opt/homebrew/bin/npm`、`/usr/local/bin/npm`。
  - `which brew`，候选 `/opt/homebrew/bin/brew`、`/usr/local/bin/brew`。
- `LocalInstallationService`/LaunchAgent plist 必须使用探测到的 Node 绝对路径。
- `检查配置 / Check` 必须显示 Node/npm/brew 探测结果；关键依赖缺失时不允许安装。
- 安装流程需要实时进度事件：
  - 创建备份。
  - 复制代理文件。
  - 写客户端配置。
  - 生成证书。
  - 信任 CA。
  - bootout/bootstrap/kickstart/print LaunchAgent。
  - 验证每个 endpoint。
- UI 需要展示实时命令日志和当前步骤，避免用户只看到“正在安装”。
- 外部命令 runner 需要 timeout 与更明确错误提示。

### 0.2.27 T18 完成记录：依赖探测、流式安装与五栏流程

本轮已按测试机反馈完成 macOS 设置 App 整改。

关键修复：

- `PreflightService` 现在探测 `node`、`npm`、`brew`、`claude`、`codex` 的真实路径和版本信息。
- `node` 是必需依赖，缺失时 `检查配置 / Check` 不通过，安装按钮保持禁用；`npm`、`brew`、`claude`、`codex` 缺失只显示橙色警告。
- `InstallationEnvironment.defaultEnvironment()` 不再写死 `/opt/homebrew/bin/node`；真实安装会先解析 Node 路径，并把解析结果写入 LaunchAgent plist。
- 新增集成测试覆盖：当环境未传 Node 路径时，安装服务解析 `/usr/local/bin/node` 并写入 plist，防止测试机 `EX_CONFIG` 问题复发。
- `CommandRunner` 增加 timeout，`launchctl` 等外部命令不会无限等待。
- `InstallationExecutionService`、`VerificationService`、`FactoryRestoreService` 支持 progress callback；UI 可实时显示当前步骤、命令、耗时、成功/失败/跳过状态。
- `VerificationService` 默认验证耗时收紧为 3 次尝试，`curl` 使用 `--connect-timeout 1 --max-time 2`，失败时更快暴露具体 endpoint。

界面调整：

- 左侧导航固定为：
  - `状态 / Status`
  - `设置 / Settings`
  - `启动配置 / Start`
  - `还原配置 / Restore`
  - `日志 / Logs`
- `状态 / Status`：展示代理状态、LaunchAgent、证书、准备状态、客户端分流路径，并内置读取 `/telemetry/summary` 的 token 用量摘要。
- `设置 / Settings`：只保留服务商设置和模型设置。
- `启动配置 / Start`：放置依赖探测、本机代理 host/port/keychain、安装启动、重新验证、客户端路径。
- `还原配置 / Restore`：独立承载 `RESTORE` 门禁与原厂服务还原。
- `日志 / Logs`：展示本次安装/还原进度与命令记录，并只读 tail `proxy.log`、`proxy.err.log`、`telemetry.jsonl`。

验证通过：

```bash
cd macos/ProxySetupApp && swift build
cd macos/ProxySetupApp && swift test
node --check claude-local-proxy/server.js
node --check claude-local-proxy/telemetry.js
node --check claude-local-proxy/keychain.js
./script/build_and_run.sh --verify
codesign --force --deep --sign - dist/ProxySetupApp.app
codesign --verify --deep --strict --verbose=2 dist/ProxySetupApp.app
ditto -c -k --keepParent dist/ProxySetupApp.app dist/ProxySetupApp-T18-FlowStreaming-20260519.zip
ditto -x -k dist/ProxySetupApp-T18-FlowStreaming-20260519.zip /tmp/proxysetupapp-t18-package-check
codesign --verify --deep --strict --verbose=2 /tmp/proxysetupapp-t18-package-check/ProxySetupApp.app
```

新测试包：

- `dist/ProxySetupApp-T18-FlowStreaming-20260519.zip`
- zip 大小：约 `2.7M`。
- SHA256：`5f6ed4922b46810eeaf66eab5e9a6a41ba99457a7607da5df41dedccb3a7f1fd`。

安全备注：

- 本轮自动化测试没有写本机真实 `~/.codex/config.toml`、`~/.claude/settings.json`、Claude Desktop config、真实 LaunchAgent 或生产 Keychain。
- `./script/build_and_run.sh --verify` 只启动 App，不点击真实安装或还原。
- `dist/` 构建产物仍被 `.gitignore` 忽略，不提交 zip。

### 0.2.28 T19 完成记录：Claude Desktop 1.7196+ 3P configLibrary 兼容修复

本轮针对测试机 `172.16.66.187` 做了只读排查，确认：

- 代理和 LaunchAgent 正常运行，LaunchAgent 已使用真实 Node 路径 `/usr/local/bin/node`。
- `https://127.0.0.1:38443/health`、`/claude-cli/health`、`/claude-desktop/health` 均返回 200。
- Claude Code CLI 已通过 `/claude-cli` 成功请求代理。
- Claude Desktop 启动后仍走 `deploymentMode: 1p`，日志出现 `app-unavailable-in-region`、bootstrap API 返回 HTML 导致 JSON parse error。
- `~/Library/Logs/Claude-3p/main.log` 不存在，代理日志没有 `/claude-desktop` 请求。

根因：

- App 写入的 Claude Desktop 3P 配置仍是旧格式：`configLibrary/cj-local-proxy.json`、`_meta.json.configs`、`gatewayBaseUrl/gatewayApiKey`。
- Claude Desktop 1.7196+ 实际要求 `_meta.json.appliedId` 是 UUID，并读取 `configLibrary/<UUID>.json`。
- 3P 配置字段要求 `inferenceProvider`、`inferenceGatewayBaseUrl`、`inferenceGatewayApiKey`、`inferenceGatewayAuthScheme`、`inferenceModels`。
- 因此 Desktop 忽略旧配置，继续按官方 1P 模式启动，导致黑屏。

已修复：

- `ClientConfigEnvironment` 增加稳定 UUID：`9f5d0b76-5b35-4c9e-9d5d-2f2a8f8f8c01`。
- Claude Desktop gateway 改为写入 `~/Library/Application Support/Claude-3p/configLibrary/<UUID>.json`。
- Gateway 内容改为新字段：
  - `inferenceProvider: gateway`
  - `inferenceGatewayBaseUrl`
  - `inferenceGatewayApiKey`
  - `inferenceGatewayAuthScheme: bearer`
  - `inferenceModels` 使用 `name` + `labelOverride`
  - `disableDeploymentModeChooser: true`
  - `unstableDisableModelVerification: true`
- `_meta.json` 同时写 `appliedId`、`entries`、`configs`、`isManaged: false`。
- 还原原厂服务同时清理新版 UUID gateway 与旧版 `cj-local-proxy.json`，并从 meta 的 `entries/configs/appliedId` 中移除本 App 管理项。

验证通过：

```bash
cd macos/ProxySetupApp && swift build
cd macos/ProxySetupApp && swift test
node --check claude-local-proxy/server.js
node --check claude-local-proxy/telemetry.js
node --check claude-local-proxy/keychain.js
./script/build_and_run.sh --verify
codesign --force --deep --sign - dist/ProxySetupApp.app
codesign --verify --deep --strict --verbose=2 dist/ProxySetupApp.app
ditto -c -k --keepParent dist/ProxySetupApp.app dist/ProxySetupApp-T19-ClaudeDesktop3P-20260519.zip
ditto -x -k dist/ProxySetupApp-T19-ClaudeDesktop3P-20260519.zip /tmp/proxysetupapp-t19-package-check
codesign --verify --deep --strict --verbose=2 /tmp/proxysetupapp-t19-package-check/ProxySetupApp.app
```

新测试包：

- `dist/ProxySetupApp-T19-ClaudeDesktop3P-20260519.zip`
- zip 大小：约 `2.7M`。
- SHA256：`df286017d7928f12e938c5a56a5a090368226bf293d126aef005e3ec57254242`。

安全备注：

- 远端测试机本轮只读排查，没有修改远端 Claude/Codex 配置或 Keychain。
- 本地自动化测试仍只使用临时目录，不写本机真实 Claude/Codex 配置、LaunchAgent 或生产 Keychain。

### 0.3 Git 状态

- 主仓库目录：`/Users/chjia/Coding/CC-CodexThirdPModels`。
- Task 14 开发 worktree：`/Users/chjia/Coding/CC-CodexThirdPModels/.worktrees/macos-install-safety`。
- Task 14 实现分支：`feature/macos-install-safety`。
- Remote：`git@github.com:MoraCJ/CC-CodexThirdPModels.git`。
- `main` 已推送到 `origin/main`。
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
