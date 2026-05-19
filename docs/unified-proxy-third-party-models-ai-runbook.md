# AI 工具执行 Runbook：通过统一代理配置 Claude Code 与 Codex 第三方模型

版本日期：2026-05-14

## 0. 任务目标

在一台 macOS 上配置一个本机 HTTPS 统一代理，让：

- Claude Code Desktop / Claude Code CLI 通过同一个本机代理使用第三方 Anthropic-compatible 模型服务。
- Codex App / Codex CLI 通过同一个本机代理使用第三方 OpenAI-compatible Responses API 入口。
- Claude 侧保留 Claude 槽位模型名；Codex 侧直接使用真实模型名。
- 通过 URL 前缀区分四类客户端来源，并在 dashboard 中分别统计模型、请求量、token usage、失败数与耗时。

标准入口如下：

| 客户端 | Base URL | Telemetry client |
| --- | --- | --- |
| Claude Code Desktop | `https://127.0.0.1:38443/claude-desktop` | `claude_desktop` |
| Claude Code CLI | `https://127.0.0.1:38443/claude-cli` | `claude_cli` |
| Codex App | `https://127.0.0.1:38443/codex-app/v1` | `codex_app` |
| Codex CLI | `https://127.0.0.1:38443/codex-cli/v1` | `codex_cli` |

无前缀旧路径仍兼容，但 telemetry 只能标记为 `claude_unknown` 或 `codex_unknown`，不应作为长期配置。

## 1. 输入参数

执行前向用户确认或从环境中读取以下参数：

| 参数 | 示例 | 说明 |
| --- | --- | --- |
| `<HOST>` | `172.16.x.x` | 目标 Mac，可为本机或 SSH 主机 |
| `<USER>` | `corptest` | 目标 Mac 用户 |
| `<PROJECT_ROOT>` | `~/Documents/Codex/claude-code-app-api` | 代理项目目录 |
| `<NODE_BIN>` | `/usr/local/bin/node` | LaunchAgent 使用的 Node 路径 |
| `<ARK_API_KEY>` | 不写入文档 | 真实 key 只能进入本机配置或环境变量 |
| `<CLAUDE_UPSTREAM>` | `https://ark.cn-beijing.volces.com/api/coding` | Anthropic-compatible endpoint |
| `<CODEX_UPSTREAM>` | `https://ark.cn-beijing.volces.com/api/coding/v3` | OpenAI-compatible endpoint |
| `<DASHBOARD_URL>` | `https://127.0.0.1:38443/dashboard` | 本机 dashboard 页面 |

## 2. 不可违反的约束

- 不要把真实 API key、密码、cookie、私钥写入 Markdown、Word、PPT、Git commit、日志摘要或最终回复。
- 修改配置前先备份：`server.js`、`telemetry.js`、`~/.claude/settings.json`、`~/.codex/config.toml`、LaunchAgent plist、Claude Desktop 3P config、`claude-ca-launcher.c`。
- 不要清空用户已有配置；只修改本任务相关字段。
- 证书私钥只保存在目标机器本地；迁移机器时优先重新生成。
- macOS System keychain 信任可能需要本机交互式 sudo，SSH 下失败时不要反复重试。
- Telemetry 只允许记录结构化指标，不记录 prompt、response 正文、Authorization、Cookie 或真实 key。

## 3. 标准模型策略

| 工具 | 客户端模型名 | 上游模型名 | 处理方式 |
| --- | --- | --- | --- |
| Claude Code | `claude-opus-4-6` | `glm-5.1` | 代理映射 |
| Claude Code | `claude-sonnet-4-6` | `kimi-k2.6` | 代理映射 |
| Claude Code | `claude-haiku-4-5` | `doubao-seed-2.0-pro` | 代理映射 |
| Codex | `doubao-seed-2.0-pro` | `doubao-seed-2.0-pro` | profile 直连 |
| Codex | `kimi-k2.6` | `kimi-k2.6` | profile 直连 |
| Codex | `glm-5.1` | `glm-5.1` | profile 直连 |

## 4. 执行步骤

### Step 1：采集现状

```bash
uname -m
command -v node || true
command -v claude || true
command -v codex || true
lsof -nP -iTCP:38443 -sTCP:LISTEN || true
lsof -nP -iTCP:38444 -sTCP:LISTEN || true
```

记录：

- 当前是否已有 38443 代理。
- 是否存在旧 38444 Codex 代理。
- Claude Desktop 是否有 `~/Library/Application Support/Claude-3p`。
- Codex 是否有 `~/.codex/config.toml`。

### Step 2：安装或更新统一代理

代理必须支持：

- `GET /health`
- `GET /healthz`
- `GET /dashboard`
- `GET /telemetry/summary`
- `GET /telemetry/events`
- 四类客户端前缀剥离：`/claude-desktop`、`/claude-cli`、`/codex-app`、`/codex-cli`
- Claude passthrough：`/v1/messages`、`/v1/messages/count_tokens`
- Codex bridge：`POST */responses` -> `https://ark.cn-beijing.volces.com/api/coding/v3/chat/completions`
- Claude slot mapping：opus/sonnet/haiku -> glm/kimi/doubao
- 脱敏 telemetry：写入 `<PROJECT_ROOT>/claude-local-proxy/logs/telemetry.jsonl`

代理代码至少包含：

```text
<PROJECT_ROOT>/claude-local-proxy/server.js
<PROJECT_ROOT>/claude-local-proxy/telemetry.js
```

如需区分 Claude Desktop Code host 与 Claude CLI，还需要准备：

```text
<PROJECT_ROOT>/claude-local-proxy/bin/claude-ca-launcher.c
<PROJECT_ROOT>/claude-local-proxy/bin/claude-ca-launcher
```

启动环境变量：

```bash
LISTEN_HOST=127.0.0.1
LISTEN_PORT=38443
UPSTREAM_BASE_URL=https://ark.cn-beijing.volces.com/api/coding
CODEX_UPSTREAM_BASE_URL=https://ark.cn-beijing.volces.com/api/coding/v3
BIG_MODEL=glm-5.1
MIDDLE_MODEL=kimi-k2.6
SMALL_MODEL=doubao-seed-2.0-pro
TLS_CERT_FILE=<PROJECT_ROOT>/claude-local-proxy/certs/server.crt
TLS_KEY_FILE=<PROJECT_ROOT>/claude-local-proxy/certs/server.key
TELEMETRY_FILE=<PROJECT_ROOT>/claude-local-proxy/logs/telemetry.jsonl
UPSTREAM_TIMEOUT_MS=300000
KEEP_ALIVE_TIMEOUT_MS=300000
HEADERS_TIMEOUT_MS=310000
```

部署后先做语法检查：

```bash
cd <PROJECT_ROOT>
node --check claude-local-proxy/server.js
node --check claude-local-proxy/telemetry.js
```

### Step 3：生成并信任本机证书

证书要求：

- server certificate SAN 包含 `127.0.0.1`、`localhost`，建议也包含 `::1`。
- Desktop/Electron 需要 Keychain 信任，不要只依赖 curl `--cacert`。
- 如果 System keychain 无法通过 SSH 写入，让用户在目标 Mac 本机执行。

验证：

```bash
curl --cacert <PROJECT_ROOT>/claude-local-proxy/certs/ca.crt https://127.0.0.1:38443/health
curl -sk https://127.0.0.1:38443/health
```

### Step 4：配置 LaunchAgent

目标文件：

```text
~/Library/LaunchAgents/com.cj.claude-local-https-proxy.plist
```

plist 必须至少包含：

- `RunAtLoad = true`
- `KeepAlive = true`
- `WorkingDirectory = <PROJECT_ROOT>/claude-local-proxy`
- stdout/stderr 指向 `<PROJECT_ROOT>/claude-local-proxy/logs/proxy.log` 与 `proxy.err.log`
- `EnvironmentVariables` 包含上一步列出的 proxy、证书、模型、timeout 和 telemetry 环境变量

加载与验证：

```bash
launchctl unload ~/Library/LaunchAgents/com.cj.claude-local-https-proxy.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/com.cj.claude-local-https-proxy.plist
launchctl kickstart -k gui/$(id -u)/com.cj.claude-local-https-proxy
launchctl print gui/$(id -u)/com.cj.claude-local-https-proxy
```

验证标准：

```text
state = running
properties = keepalive | runatload
```

这一步很关键：只看到 `38443` 正在监听不等于开机/登录后会自动启动。必须看 `launchctl print` 的 `runatload` 与 `keepalive`。

### Step 5：配置 Claude Code

Desktop 3P Gateway：

```json
{
  "inferenceProvider": "gateway",
  "inferenceGatewayBaseUrl": "https://127.0.0.1:38443/claude-desktop",
  "inferenceGatewayApiKey": "CJ_LOCAL_PROXY_TOKEN",
  "inferenceGatewayAuthScheme": "bearer",
  "inferenceModels": [
    { "name": "claude-sonnet-4-6", "labelOverride": "Sonnet 4.6" },
    { "name": "claude-opus-4-6", "labelOverride": "Opus 4.6" },
    { "name": "claude-haiku-4-5", "labelOverride": "Haiku 4.5" }
  ],
  "disableDeploymentModeChooser": true,
  "unstableDisableModelVerification": true
}
```

Claude Desktop 1.7196+ 要求 `configLibrary/_meta.json` 的 `appliedId` 是 UUID，并读取 `configLibrary/<UUID>.json`；非 UUID 的旧配置 ID 会被忽略。

CLI/host settings：

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://127.0.0.1:38443/claude-cli",
    "ANTHROPIC_AUTH_TOKEN": "<ARK_API_KEY>",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-4-6",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-4-6",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4-5",
    "NODE_USE_SYSTEM_CA": "1",
    "NODE_EXTRA_CA_CERTS": "<PROJECT_ROOT>/claude-local-proxy/certs/ca.crt",
    "SSL_CERT_FILE": "<PROJECT_ROOT>/claude-local-proxy/certs/ca.crt"
  }
}
```

检查项：

- Desktop 3P Gateway 必须指向 `https://127.0.0.1:38443/claude-desktop`。
- CLI `ANTHROPIC_BASE_URL` 必须是 `https://127.0.0.1:38443/claude-cli`。
- 不应保留 `ANTHROPIC_MODEL`。
- 不应保留旧 `modelOverrides`。
- `ANTHROPIC_DEFAULT_*_MODEL` 写 Claude 槽位名，不写真实模型名。

#### Claude Desktop Code host 区分

Claude Desktop 内置 Code host 有时会调用自己的 `claude` binary。为了让 Desktop host 也落到 `claude_desktop` 而不是 `claude_cli`，可使用 `claude-ca-launcher` 包一层真实 CLI：

```c
setenv("NODE_USE_SYSTEM_CA", "1", 1);
setenv("NODE_EXTRA_CA_CERTS", ca, 1);
setenv("SSL_CERT_FILE", ca, 0);
setenv("ANTHROPIC_BASE_URL", "https://127.0.0.1:38443/claude-desktop", 1);
execv("/opt/homebrew/bin/claude", next_argv);
```

编译并替换 Desktop 期望路径：

```bash
cc <PROJECT_ROOT>/claude-local-proxy/bin/claude-ca-launcher.c \
  -o <PROJECT_ROOT>/claude-local-proxy/bin/claude-ca-launcher
chmod +x <PROJECT_ROOT>/claude-local-proxy/bin/claude-ca-launcher

# 版本号以 Claude Desktop 日志 `[CCD] Initialized with version ...` 为准
ln -sf <PROJECT_ROOT>/claude-local-proxy/bin/claude-ca-launcher \
  "$HOME/Library/Application Support/Claude-3p/claude-code/<VERSION>/claude"
ln -sf <PROJECT_ROOT>/claude-local-proxy/bin/claude-ca-launcher \
  "$HOME/Library/Application Support/Claude-3p/claude-code/<VERSION>/claude.app/Contents/MacOS/claude"
touch "$HOME/Library/Application Support/Claude-3p/claude-code/<VERSION>/.verified"
```

迁移到新电脑时不要硬套 `<VERSION>`，先读 Desktop 日志确认版本目录。

### Step 6：配置 Codex

目标文件：

```text
~/.codex/config.toml
```

标准配置：

```toml
model_provider = "ark-coding-app"
model = "doubao-seed-2.0-pro"
model_reasoning_effort = "medium"
disable_response_storage = true

[model_providers.ark-coding-app]
name = "Volcengine Ark Coding via unified local proxy - Codex App"
wire_api = "responses"
requires_openai_auth = true
base_url = "https://127.0.0.1:38443/codex-app/v1"
supports_websockets = false

[model_providers.ark-coding-cli]
name = "Volcengine Ark Coding via unified local proxy - Codex CLI"
wire_api = "responses"
requires_openai_auth = true
base_url = "https://127.0.0.1:38443/codex-cli/v1"
supports_websockets = false

[profiles.ark-doubao]
model_provider = "ark-coding-cli"
model = "doubao-seed-2.0-pro"
model_reasoning_effort = "medium"

[profiles.ark-kimi]
model_provider = "ark-coding-cli"
model = "kimi-k2.6"
model_reasoning_effort = "high"

[profiles.ark-glm]
model_provider = "ark-coding-cli"
model = "glm-5.1"
model_reasoning_effort = "high"
```

检查项：

- App 默认 provider 名为 `ark-coding-app`，base URL 为 `https://127.0.0.1:38443/codex-app/v1`。
- CLI profiles 使用 provider `ark-coding-cli`，base URL 为 `https://127.0.0.1:38443/codex-cli/v1`。
- 两个 provider 都必须有 `wire_api = "responses"`。
- profiles 使用真实模型名。

### Step 6.1：Codex CLI 与 Codex App 切换模型

Codex CLI 用 profile 切换：

```bash
codex -p ark-doubao
codex -p ark-kimi
codex -p ark-glm
```

Codex App 推荐两种方式：

1. 修改 `~/.codex/config.toml` 顶层默认模型，然后退出并重新打开 Codex App。适合长期默认切换。
2. 启动 App 时用 `-c key=value` 临时覆盖。适合一次性打开指定 workspace。

```bash
# 以 Kimi profile 对应模型打开某个 workspace
codex app /path/to/project \
  -c 'model_provider="ark-coding-app"' \
  -c 'model="kimi-k2.6"' \
  -c 'model_reasoning_effort="high"'

# 以 Doubao 打开某个 workspace
codex app /path/to/project \
  -c 'model_provider="ark-coding-app"' \
  -c 'model="doubao-seed-2.0-pro"' \
  -c 'model_reasoning_effort="medium"'

# 以 GLM 打开某个 workspace
codex app /path/to/project \
  -c 'model_provider="ark-coding-app"' \
  -c 'model="glm-5.1"' \
  -c 'model_reasoning_effort="high"'
```

注意：当前已打开会话不保证热切换模型。验证时新开会话或重启 App，再看 dashboard 或 telemetry 中的 `client=codex_app` / `client=codex_cli` 是否分开落点，同时看代理日志中的 `codex responses model <客户端模型> -> <上游模型>`。

### Step 7：验证

```bash
lsof -nP -iTCP:38443 -sTCP:LISTEN
curl -sk https://127.0.0.1:38443/health
curl -sk https://127.0.0.1:38443/dashboard
curl -sk https://127.0.0.1:38443/telemetry/summary
curl -sk https://127.0.0.1:38443/claude-desktop/health
curl -sk https://127.0.0.1:38443/claude-cli/health
curl -sk https://127.0.0.1:38443/codex-app/health
curl -sk https://127.0.0.1:38443/codex-cli/health
launchctl print gui/$(id -u)/com.cj.claude-local-https-proxy
tail -n 160 <PROJECT_ROOT>/claude-local-proxy/logs/proxy.log
codex -p ark-doubao
codex -p ark-kimi
codex -p ark-glm
```

Claude Desktop 额外看：

```bash
tail -n 200 "$HOME/Library/Logs/Claude-3p/main.log"
```

如果 Desktop data root 不是默认 `Claude-3p`，以 macOS 设置 App `启动配置 / Start` 中的 `Data root` 为准。T20 版 App 会在 `Claude Desktop Host / Desktop 运行组件` 里显示当前 data root、host version、`.verified` 和 host binary 检查结果。

成功信号：

- `launchctl print` 显示 `state = running`，并出现 `properties = keepalive | runatload`。
- `/health` 返回 `ok`、`codexUpstream`、`telemetryFile`、`dashboard`、`clientPrefixes`。
- `/dashboard` 返回 `Proxy Usage Dashboard / 代理用量看板`。
- `/telemetry/summary` 返回 JSON summary。
- 四个前缀 health 均返回 ok。
- `ConfigHealth recomputed { state: 'healthy', provider: 'gateway' }`
- `POST /v1/messages -> 200`
- `codex responses model doubao-seed-2.0-pro -> doubao-seed-2.0-pro`
- `codex responses model kimi-k2.6 -> kimi-k2.6`
- `codex responses model glm-5.1 -> glm-5.1`
- Codex tool call 能完成 `function_call` / `function_call_output` 往返。
- Dashboard 最近请求中能区分 `claude_desktop`、`claude_cli`、`codex_app`、`codex_cli`。如果出现 `*_unknown`，说明仍有客户端在使用无前缀旧 URL。

## 5. 故障决策树

1. `/health` 不通：先查 LaunchAgent state、38443 端口、`proxy.err.log`。
2. `/health` 通但 Claude unhealthy：查 Keychain 信任、Desktop 3P config、`main.log`。
3. Dashboard 打不开：先查 `/dashboard`、`/telemetry/summary`，再确认 `server.js` 是否为带 telemetry 的新版本。
4. Dashboard 出现 `claude_unknown` 或 `codex_unknown`：对应客户端仍在使用无前缀 URL，检查 Desktop Gateway、`~/.claude/settings.json`、`~/.codex/config.toml` 和 `claude-ca-launcher`。
5. Claude 模型不对：查 `ANTHROPIC_MODEL`、`modelOverrides`、代理映射日志。
6. Codex 不通：查 `~/.codex/config.toml`、Authorization、`/v1/responses` 分支日志。
7. Codex tool call 不通：查 Responses bridge 的 tool 转换逻辑。
8. Claude CLI 可用但 Desktop 无回复或提示 host binary 不存在：检查 Desktop Host 面板；若 `downloads.claude.ai` 下载失败，用 App 初始化本机 `claude-ca-launcher` 软链和 `.verified`。
9. Cowork 显示 server busy：查 transcript 真实错误；若是 SSL，安装 `claude-ca-launcher`。
10. 重启后代理没起来：查 plist 是否包含 `RunAtLoad` 与 `KeepAlive`，再查 `launchctl print` 的 `last exit code`、`proxy.err.log` 和证书路径。

## 6. 回滚步骤

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.cj.claude-local-https-proxy.plist 2>/dev/null || true
```

然后按备份恢复：

- `<PROJECT_ROOT>/claude-local-proxy/server.js.bak.*`
- `<PROJECT_ROOT>/claude-local-proxy/telemetry.js.bak.*`
- `<PROJECT_ROOT>/claude-local-proxy/bin/claude-ca-launcher.c.bak.*`
- `~/.claude/settings.json.bak.*`
- `~/.codex/config.toml.bak.*`
- `~/Library/Application Support/Claude-3p/configLibrary/*.json.bak.*`
- `~/Library/Application Support/<Desktop data root>/claude-code/<version>` 中本 App 创建的 `claude-ca-launcher` 软链和 `.verified`，如需彻底移除 Desktop Host 兜底可手工清理。
- 如需双代理模式，恢复旧 Codex LaunchAgent，并确认 38444 重新监听。

回滚后仍要分别验证 Claude 和 Codex，不要只看进程存在。

## 7. 交付输出格式

执行完成后，给用户输出：

- 修改了哪些文件。
- 当前监听端口。
- LaunchAgent 是否 `state = running` 且包含 `keepalive | runatload`。
- Claude 和 Codex 各自成功信号。
- profiles 是否通过。
- Dashboard URL、telemetry 文件路径，以及是否能区分四类客户端。
- 是否存在未完成的证书信任、Cowork 或网络下载问题。
- 所有敏感值均以 `<REDACTED>` 或占位符呈现。
