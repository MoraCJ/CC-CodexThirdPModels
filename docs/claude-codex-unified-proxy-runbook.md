# Claude + Codex 统一本机代理 Handoff Runbook

一个本机 HTTPS 代理同时服务 Claude Code Desktop/CLI 与 Codex CLI/App

更新时间：2026-05-14

> 本文基于原 `handoff.md`、远端 Mac 当前状态与本轮验证结果整理；不包含真实 API key、密码或私钥。

## 1. Handoff 摘要

- 已把 Codex 代理逻辑合进 Claude 本机 HTTPS 代理，远端 Mac 当前只保留 `https://127.0.0.1:38443` 作为统一入口。
- Claude 仍使用 Claude 槽位名，由代理映射到真实上游模型；Codex 直接使用真实模型名，通过 profile 切换。
- 代理已新增 dashboard 与脱敏 telemetry，支持区分 Claude Desktop、Claude CLI、Codex App、Codex CLI 四类来源。
- 远端 LaunchAgent 已验证包含 `keepalive | runatload`，登录后会自动启动并保持运行。
- 旧 Codex 独立代理端口 `38444` 已停止监听，旧文件保留作为回滚参考。
- 验证结果显示 Claude `/v1/messages`、Codex `/v1/responses`、Codex profile 与 tool call 均可用。
- 本文不包含真实 API key、密码或私钥；需要配置时统一使用 `<ARK_API_KEY>` 占位。

## 2. 当前架构

```text
Claude Desktop  -> https://127.0.0.1:38443/claude-desktop -> /v1/messages
Claude CLI      -> https://127.0.0.1:38443/claude-cli     -> /v1/messages
Codex App       -> https://127.0.0.1:38443/codex-app/v1   -> /v1/responses
Codex CLI       -> https://127.0.0.1:38443/codex-cli/v1   -> /v1/responses

All four prefixes enter:
  LaunchAgent + local HTTPS cert
    -> claude-local-proxy/server.js

Claude path: passthrough to https://ark.cn-beijing.volces.com/api/coding
Codex path: Responses API -> Chat Completions -> https://ark.cn-beijing.volces.com/api/coding/v3/chat/completions -> Responses API
Dashboard: https://127.0.0.1:38443/dashboard
Telemetry: <PROJECT_ROOT>/claude-local-proxy/logs/telemetry.jsonl
```

### 2.1 组件清单

| 组件 | 位置 | 作用 | 备注 |
| --- | --- | --- | --- |
| 目标 Mac | 172.16.66.188 / corptest | 当前可用环境 | 材料中不保存登录密码 |
| 统一代理 | /Users/corptest/Documents/Codex/claude-code-app-api/claude-local-proxy/server.js | Claude + Codex 共同入口 | 监听 127.0.0.1:38443 |
| Telemetry helper | /Users/corptest/Documents/Codex/claude-code-app-api/claude-local-proxy/telemetry.js | 来源识别、usage 归一化、JSONL 聚合 | 不记录 prompt/response/key |
| LaunchAgent | /Users/corptest/Library/LaunchAgents/com.cj.claude-local-https-proxy.plist | 登录后自动拉起代理 | stdout/stderr 写入 proxy logs |
| Claude Desktop 3P | /Users/corptest/Library/Application Support/Claude-3p/configLibrary/*.json | Desktop Gateway 配置 | base URL 指向 /claude-desktop |
| Claude CLI settings | /Users/corptest/.claude/settings.json | Claude Code CLI 配置 | base URL 指向 /claude-cli |
| Claude Desktop launcher | claude-local-proxy/bin/claude-ca-launcher | Desktop host 证书与来源兜底 | 注入 /claude-desktop |
| Codex config | /Users/corptest/.codex/config.toml | Codex provider + profiles | App 用 ark-coding-app，CLI 用 ark-coding-cli |
| 旧 Codex 代理 | /Users/corptest/.codex/ark-coding-proxy/server.js | 回滚参考 | 38444 当前不应监听 |

### 2.2 代理路由

| 路径 | 方法 | 服务对象 | 行为 |
| --- | --- | --- | --- |
| /health | GET | 本机健康检查 | 返回 Claude upstream、Codex upstream 与模型映射 |
| /healthz | GET | 轻量健康检查 | 返回 ok |
| /dashboard | GET | 用量看板 | 中英双语 dashboard，按 client/tool/model 聚合 |
| /telemetry/summary | GET | 用量 API | 返回 summary 与最近事件 |
| /telemetry/events | GET | 用量 API | 返回最近事件 |
| /claude-desktop/* | 任意 | Claude Desktop | 剥离前缀后走 Claude 分支，telemetry client 为 claude_desktop |
| /claude-cli/* | 任意 | Claude CLI | 剥离前缀后走 Claude 分支，telemetry client 为 claude_cli |
| /codex-app/v1/* | 任意 | Codex App | 剥离前缀后走 Codex 分支，telemetry client 为 codex_app |
| /codex-cli/v1/* | 任意 | Codex CLI | 剥离前缀后走 Codex 分支，telemetry client 为 codex_cli |
| */responses | POST | Codex Responses API | 转换为 Chat Completions 再请求 Ark coding v3 |
| 其他路径 | 任意 | Claude Anthropic-compatible API | 透传请求并做 Claude 槽位模型映射 |

## 3. 模型策略

Claude 侧保留槽位模型名，便于 Desktop / CLI 兼容；Codex 侧直接使用真实模型名，避免再做一层 Claude-style 映射。

| 工具 | 客户端模型名 | 代理/上游模型名 | 用途建议 |
| --- | --- | --- | --- |
| Claude | claude-opus-4-6 | glm-5.1 | 复杂推理/高质量输出 |
| Claude | claude-sonnet-4-6 | kimi-k2.6 | 默认主力模型 |
| Claude | claude-haiku-4-5 | doubao-seed-2.0-pro | 快速/低成本任务 |
| Codex profile ark-doubao | doubao-seed-2.0-pro | doubao-seed-2.0-pro | 默认与快速任务 |
| Codex profile ark-kimi | kimi-k2.6 | kimi-k2.6 | 编码与复杂修改 |
| Codex profile ark-glm | glm-5.1 | glm-5.1 | 高质量推理任务 |

## 4. Codex 多模型配置

Codex 通过 provider + profiles 实现多模型切换。关键配置如下，真实 API key 不写入本文。

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

常用切换方式：

```bash
codex -p ark-doubao
codex -p ark-kimi
codex -p ark-glm
```

## 5. 已验证结果

| 检查项 | 信号 | 状态 |
| --- | --- | --- |
| 端口 | lsof 显示 127.0.0.1:38443 LISTEN | 通过 |
| 旧端口 | 127.0.0.1:38444 不再 LISTEN | 通过 |
| 健康检查 | curl -sk https://127.0.0.1:38443/health | 通过 |
| 自动启动 | launchctl print 显示 keepalive 与 runatload | 通过 |
| Dashboard | /dashboard 返回中英双语用量看板 | 通过 |
| Telemetry | /telemetry/summary 返回 JSON summary | 通过 |
| 来源前缀 | /claude-desktop/health、/claude-cli/health、/codex-app/health、/codex-cli/health | 通过 |
| Claude | /v1/messages 返回 200，日志出现槽位映射 | 通过 |
| Codex default | 默认 doubao-seed-2.0-pro 能回复 | 通过 |
| Codex profiles | ark-doubao / ark-kimi / ark-glm 均能回复 | 通过 |
| Tool call | Codex tool call pwd 等测试可用 | 通过 |

## 6. 日常操作

### 6.1 检查 LaunchAgent

```bash
launchctl print gui/$(id -u)/com.cj.claude-local-https-proxy
```

关键成功信号：

```text
state = running
properties = keepalive | runatload
```

这表示代理会在用户登录后自动启动，并由 `KeepAlive` 保持运行。

### 6.2 重启统一代理

```bash
launchctl kickstart -k gui/$(id -u)/com.cj.claude-local-https-proxy
```

### 6.3 检查端口

```bash
lsof -nP -iTCP:38443 -sTCP:LISTEN
lsof -nP -iTCP:38444 -sTCP:LISTEN
```

### 6.4 检查健康状态

```bash
curl -sk https://127.0.0.1:38443/health
curl -sk https://127.0.0.1:38443/healthz
curl -sk https://127.0.0.1:38443/claude-desktop/health
curl -sk https://127.0.0.1:38443/claude-cli/health
curl -sk https://127.0.0.1:38443/codex-app/health
curl -sk https://127.0.0.1:38443/codex-cli/health
```

### 6.5 检查 Dashboard 与 Telemetry

```bash
curl -sk https://127.0.0.1:38443/dashboard
curl -sk https://127.0.0.1:38443/telemetry/summary
tail -n 20 /Users/corptest/Documents/Codex/claude-code-app-api/claude-local-proxy/logs/telemetry.jsonl
```

Dashboard 页面标题应包含 `Proxy Usage Dashboard / 代理用量看板`。如果 telemetry 中出现 `claude_unknown` 或 `codex_unknown`，说明仍有客户端在使用无前缀旧 URL。

### 6.6 查看代理日志

```bash
tail -n 160 /Users/corptest/Documents/Codex/claude-code-app-api/claude-local-proxy/logs/proxy.log
tail -n 80 /Users/corptest/Documents/Codex/claude-code-app-api/claude-local-proxy/logs/proxy.err.log
```

### 6.7 Codex profile smoke test

```bash
codex -p ark-doubao
codex -p ark-kimi
codex -p ark-glm
```

## 7. 故障排查

| 问题 | 处理建议 |
| --- | --- |
| health 不通 | 先看 LaunchAgent state，再看 38443 端口和 proxy.err.log；证书文件路径错误也会导致代理无法启动。 |
| 重启或登录后代理没起来 | 检查 plist 是否包含 RunAtLoad 和 KeepAlive；`launchctl print` 应显示 `properties = keepalive | runatload`。 |
| Dashboard 没有数据 | 先触发一次 Claude/Codex 请求，再看 `logs/telemetry.jsonl`；确认 `telemetry.js` 已部署且 `TELEMETRY_FILE` 路径可写。 |
| Dashboard 出现 `*_unknown` | 检查对应客户端是否还在使用无前缀旧 URL，应改为 /claude-desktop、/claude-cli、/codex-app/v1 或 /codex-cli/v1。 |
| Claude App 显示 gateway unhealthy | 检查 Desktop 3P config base URL 是否为 https://127.0.0.1:38443/claude-desktop；再看 main.log 里的 ConfigHealth。 |
| Claude 调用到了错误模型 | 检查请求模型名是否包含 opus/sonnet/haiku；代理只对 Claude 槽位名做映射。 |
| Codex 401/403 | 检查 Codex provider token 或环境变量；App 应走 ark-coding-app，CLI profiles 应走 ark-coding-cli；不要把真实 key 写进 server.js 或文档。 |
| Codex tool call 异常 | 重点看 /responses 转换：function_call、function_call_output、tools 参数是否被正确转换。 |
| 上游超时 | 确认公司网络到 ark.cn-beijing.volces.com 可达；必要时调大 UPSTREAM_TIMEOUT_MS。 |

## 8. 回滚方案

1. 停止当前统一代理：`launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.cj.claude-local-https-proxy.plist`。
2. 恢复代理备份：`server.js.bak.codex-merge.20260514144040`。
3. 恢复 Codex 配置备份：`~/.codex/config.toml.bak.unified.20260514145435` 或 `~/.codex/config.toml.bak.real-profiles.20260514150226`。
4. 如必须回到双代理模式，再重新加载旧 `com.cj.codex-ark-coding-proxy.plist` 并确认 38444 监听。
5. 回滚后分别跑 Claude 与 Codex smoke test；不要只看端口存在。

## 9. 安全与分享边界

- 文档、PPT、runbook 不保存真实 API key、SSH 密码、私钥内容。
- 私钥文件如 `certs/server.key` 只保留在目标 Mac；迁移时优先重新生成证书。
- 代理日志公开前先检查 authorization、cookie、个人路径等敏感内容。
- API key 不写死在 `server.js`；优先由客户端配置或环境变量提供。
- 远程 SSH 密码应在完成配置后轮换或替换为 SSH key。

## 10. 后续建议

- 把远端合并后的 `server.js` 同步回材料仓库，避免本地源码与目标 Mac 实际状态分叉。
- 为统一代理补一个最小自动化 smoke test：health、Claude slot mapping、Codex profiles、tool call。
- 把安装动作脚本化：证书生成/信任、LaunchAgent、Claude config、Codex config、回滚备份。
