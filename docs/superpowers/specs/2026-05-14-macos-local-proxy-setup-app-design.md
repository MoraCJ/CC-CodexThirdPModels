# macOS 本机代理设置 App 设计

日期：2026-05-14

## 目标

开发第一版 macOS App，让用户可以在自己的 Mac 上完成本机 HTTPS 统一代理的安装、配置、运行和验证，不再需要手工照着 runbook 修改 plist、JSON、TOML、证书和 shell 环境。

这个 App 负责把 Claude Code Desktop/CLI 与 Codex App/CLI 配置到现有本机统一代理架构上，并允许用户自己输入第三方模型服务商的 Base URL、API Key 和模型名。

第一版只支持本机部署，不支持远程 SSH 部署。

## 用户

主要用户是正在给一台新 Mac 配置 Claude Code 与 Codex 第三方模型服务的人。用户能够提供服务商凭据和模型名，但不应该被要求手工编辑 LaunchAgent、证书、Claude 配置或 Codex 配置。

## 产品形态

App 使用 SwiftUI 开发，包含三个主要界面：

- 初次安装和配置用的设置向导。
- 日常检查用的主状态页。
- 菜单栏入口，用于快速查看状态和执行常用操作。

第一版以普通本地 macOS App 方式交付开发和测试。签名 `.pkg` 安装包可以后续再做，不属于 v1 必须范围。

## 当前 v1 实现状态

截至 2026-05-15，`macos/ProxySetupApp` 已具备第一版本机设置程序的主体：

- 主窗口与菜单栏入口。
- 状态页展示 Proxy、LaunchAgent、证书、Keychain 和四类客户端分流路径。
- 设置向导支持 Anthropic-compatible / OpenAI-compatible 类型选择。
- 用户可输入 Claude/Codex Base URL、API Key、Keychain account 和模型名。
- API Key 只通过显式按钮保存到 macOS Keychain，保存后清空明文输入框。
- Codex profiles 可新增、删除，并选择 reasoning effort。
- 验证页展示 health、dashboard、telemetry summary 和四类客户端 health URL。
- 验证页展示 Claude/Codex 配置预览，预览中只包含 `CJ_LOCAL_PROXY_TOKEN`，不包含真实 provider API Key。
- LaunchAgent service 生成 `RunAtLoad` / `KeepAlive` plist，并生成 launchctl 控制命令数组。
- Certificate service 生成 OpenSSL 证书命令和 login keychain 信任命令数组。
- LocalInstallationService 生成本机安装计划，并可在注入的临时目录中准备代理文件、运行配置、证书配置和 LaunchAgent plist。
- 设置向导验证页展示安装计划与安全边界，配置无效时展示错误原因。

当前自动化验证仍不会写真实 `~/.codex/config.toml`、`~/.claude/settings.json`、Claude Desktop config、`~/Library/LaunchAgents` 或生产 Keychain 项。真实安装执行路径应在 App UI 中由用户显式点击触发，并保留备份与回滚。
Task 13 只实现安装编排、命令预览和临时目录文件准备，不执行真实 `launchctl`、`security add-trusted-cert` 或 `openssl`。

## 支持的配置

App 允许用户配置以下内容。

Claude 配置：

- 是否启用 Claude 配置。
- Anthropic-compatible Base URL。
- API Key。
- Opus 槽位对应的上游模型名。
- Sonnet 槽位对应的上游模型名。
- Haiku 槽位对应的上游模型名。

Codex 配置：

- 是否启用 Codex 配置。
- OpenAI-compatible Base URL。
- API Key。
- 一个或多个模型 profile，每个 profile 包含显示名、模型名和 reasoning effort。

本机代理配置：

- Listen host，默认 `127.0.0.1`。
- Listen port，默认 `38443`。
- 安装目录，默认放在当前用户的 Application Support 目录下。

生成后的客户端 Base URL 固定保持为：

| 客户端 | Base URL |
| --- | --- |
| Claude Code Desktop | `https://127.0.0.1:38443/claude-desktop` |
| Claude Code CLI | `https://127.0.0.1:38443/claude-cli` |
| Codex App | `https://127.0.0.1:38443/codex-app/v1` |
| Codex CLI | `https://127.0.0.1:38443/codex-cli/v1` |

这些前缀必须稳定保留，因为 dashboard telemetry 依赖它们区分客户端来源。

## 设置向导

设置向导分为七步。

1. 环境检查
   - 检测 CPU 架构、macOS 版本、Node.js、Claude CLI、Codex CLI、`38443` 端口占用、现有代理文件、现有 LaunchAgent，以及现有 Claude/Codex 配置文件。
   - 用清晰的通过、警告、错误状态展示结果。

2. Provider 设置
   - 收集 Claude 和 Codex 的服务商配置。
   - 校验 Base URL 是否为合法 HTTPS URL。
   - 将 API Key 存入 macOS Keychain。
   - 保存后清空明文输入框，并只显示保存状态与 account，不显示真实 key。

3. 模型映射
   - Claude 侧把 Opus、Sonnet、Haiku 三个槽位映射到用户输入的真实上游模型名。
   - Codex 侧创建可编辑 profile，每个 profile 指向用户输入的真实模型名。

4. 代理安装
   - 安装或更新本机代理文件。
   - 包含 `server.js`、`telemetry.js`、测试文件和 `claude-ca-launcher.c`。
   - 创建证书目录和日志目录。

5. 证书设置
   - 生成本机 CA 和 server certificate。
   - server certificate 的 SAN 包含 `127.0.0.1`、`localhost` 和 `::1`。
   - 引导用户在 macOS Keychain 中信任 CA。
   - 不反复触发静默权限请求。

6. 客户端配置
   - 备份并更新 Claude Desktop gateway 配置。
   - 备份并更新 `~/.claude/settings.json`。
   - 备份并更新 `~/.codex/config.toml`。
   - 在需要区分 Claude Desktop Code host 时，编译并安装 `claude-ca-launcher`。

7. 启动与验证
   - 创建或更新 LaunchAgent。
   - 确保 `RunAtLoad` 和 `KeepAlive` 启用。
   - 启动代理。
   - 验证 health endpoint、四类客户端前缀 health endpoint、dashboard、telemetry summary 和 LaunchAgent 状态。
   - 在执行前展示 launchctl 与证书信任命令预览，避免用户不清楚 App 将进行哪些本机修改。

## 主状态页

主状态页展示运行状态：

- Proxy / 代理：未安装、已停止、运行中、不健康。
- LaunchAgent / 开机启动：缺失、未启用、已启用并运行、配置异常。
- Certificate / 证书：缺失、已生成、已信任、未信任。
- Claude Desktop：已配置或需要处理。
- Claude CLI：已配置或需要处理。
- Codex App：已配置或需要处理。
- Codex CLI：已配置或需要处理。

主要操作：

- 安装或更新。
- 启动。
- 停止。
- 重启。
- 运行验证。
- 打开 dashboard。
- 打开日志。
- 回滚最近一次配置备份。

## 菜单栏

菜单栏入口提供：

- 紧凑健康状态。
- 代理运行或停止状态。
- 快捷操作：打开 App、打开 dashboard、重启代理、运行验证。

菜单栏入口只做快速操作，不隐藏关键错误。完整错误详情仍在主窗口展示。

## 数据与密钥

API Key 必须存入 macOS Keychain。

真实上游 API Key 不写入 Claude 配置、Codex 配置、LaunchAgent plist 或 App 管理的明文配置文件。代理启动时通过 App 创建的稳定 service/account 名称从 Keychain 读取真实 key。客户端配置如果必须存在 auth 字段，只写入非敏感的本地占位 token。

App 不得把 API Key、SSH 密码、Cookie、Authorization header、prompt 或模型响应正文写入：

- Markdown 文档。
- handoff 文件。
- App 日志。
- 代理 telemetry。
- 诊断导出。

Telemetry 只记录结构化信息：

- 时间。
- 工具和客户端。
- 请求类型。
- 客户端模型名。
- 上游模型名。
- 状态码。
- 耗时。
- 上游返回的 token usage。
- 错误类型。

## 文件归属

推荐 App 管理目录：

```text
~/Library/Application Support/CJLocalProxy/
~/Library/Application Support/CJLocalProxy/claude-local-proxy/
~/Library/Application Support/CJLocalProxy/config/
~/Library/Application Support/CJLocalProxy/backups/
~/Library/LaunchAgents/com.cj.claude-local-https-proxy.plist
```

App 修改用户配置文件前必须备份：

```text
~/.claude/settings.json
~/.codex/config.toml
~/Library/Application Support/Claude-3p/configLibrary/*.json
~/Library/LaunchAgents/com.cj.claude-local-https-proxy.plist
```

备份文件名包含时间戳。由 App 生成的备份不应该包含 App 导出的明文真实 API Key。

## 架构

macOS App 负责安装、配置、验证和运维编排。现有 Node.js 代理继续负责 HTTP 代理行为和 telemetry。

组件划分：

- `SetupApp`：SwiftUI UI、状态模型、设置向导、主状态页和菜单栏入口。
- `PreflightService`：检测工具、端口、文件和 LaunchAgent 状态。
- `KeychainService`：保存和读取 API Key。
- `ProxyInstaller`：复制代理文件、创建目录、写入 App 管理的非敏感配置，并执行语法检查。
- `CertificateService`：生成本机 CA/server 证书，并引导信任流程。
- `ClientConfigService`：读取、备份、更新和验证 Claude/Codex 配置。
- `LaunchAgentService`：写入、加载、卸载、启动、停止和验证 LaunchAgent。
- `VerificationService`：调用 health endpoint 并汇总验证结果。
- `LogService`：读取 App 和代理日志，并做脱敏。

代理读取 App 管理的非敏感运行配置，并从 Keychain 读取真实上游 API Key。代理仍必须对所有 auth 相关值做日志和 telemetry 脱敏。

## 错误处理

错误按用户正在执行的动作分组展示：

- 环境缺失：说明缺少哪个工具，以及用户应该去哪里安装。
- 端口冲突：展示占用端口的进程，并允许用户选择换端口，或在安全时停止当前代理。
- 证书未信任：解释 Keychain 信任步骤，并在用户完成后重新检查。
- 配置写入失败：展示文件路径并保留备份。
- LaunchAgent 启动失败：展示 `launchctl print` 摘要、last exit code 和最近 stderr。
- 代理不健康：展示 `/health`、`/telemetry/summary` 和最近 `proxy.err.log` 摘要。

App 不以删除用户配置作为修复策略。回滚只恢复 App 自己创建的最近备份。

## 验证

安装或更新后，App 运行以下验证：

```bash
node --check claude-local-proxy/server.js
node --check claude-local-proxy/telemetry.js
curl -sk https://127.0.0.1:38443/health
curl -sk https://127.0.0.1:38443/dashboard
curl -sk https://127.0.0.1:38443/telemetry/summary
curl -sk https://127.0.0.1:38443/claude-desktop/health
curl -sk https://127.0.0.1:38443/claude-cli/health
curl -sk https://127.0.0.1:38443/codex-app/health
curl -sk https://127.0.0.1:38443/codex-cli/health
launchctl print gui/$(id -u)/com.cj.claude-local-https-proxy
```

成功标准：

- Proxy health 返回 `ok`。
- Dashboard 返回双语 dashboard HTML。
- Telemetry summary 返回 JSON。
- 四个前缀 health endpoint 都返回 `ok`。
- LaunchAgent 正在运行，并包含 `keepalive | runatload`。

## 测试策略

实现时应包含：

- 配置文件转换单元测试。
- 脱敏逻辑单元测试。
- Provider 和模型名校验单元测试。
- LaunchAgent plist 生成单元测试。
- Keychain wrapper 测试，尽量使用测试专用 service/account namespace。
- 本地手工验证用的 integration-style 命令。

当前开发机器只安装 CommandLineTools，没有完整 Xcode，也没有 XCTest。SwiftPM tests 使用 Swift Testing（`import Testing`、`@Test`、`#expect`），并在 package test target 中加入 CommandLineTools 的 `Testing.framework` 和 `lib_TestingInterop.dylib` rpath。

开发和测试期间不得修改本机真实 `~/.codex/config.toml`、`~/.claude/settings.json`、Claude Desktop config、`~/Library/LaunchAgents` 或生产 Keychain 项。涉及文件写入的测试必须使用临时目录或 fixture；Keychain 测试必须使用测试专用 service/account namespace。

现有 Node 代理测试继续保留：

```bash
node --test claude-local-proxy/tests/telemetry.test.js
node --check claude-local-proxy/server.js
node --check claude-local-proxy/telemetry.js
```

## v1 不做的范围

- 远程 SSH 部署。
- 多机器批量管理。
- 签名 `.pkg` 安装包。
- 自动安装 Node.js、Claude Code 或 Codex。
- 云同步。
- 编辑上游 provider 账号。
- 记录 prompt 或 response 正文。
- 支持非 macOS 平台。

## v1 实现决策

第一版按以下决策实现：

- 在 `macos/ProxySetupApp/` 下创建 SwiftUI Xcode project。
- 开发阶段把代理源文件随 App 一起打包。
- 安装或更新时，将打包的代理文件复制到 `~/Library/Application Support/CJLocalProxy/claude-local-proxy/`。
- 真实 provider API Key 存入 Keychain。
- 代理启动时从 Keychain 读取真实 provider API Key。
- Claude 或 Codex 客户端需要 auth 字段时，只写入非敏感本地占位 token。
