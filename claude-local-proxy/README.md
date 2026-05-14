# Claude + Codex Local HTTPS Proxy

本地 HTTPS 反向代理，用于 Claude Code Desktop/CLI 与 Codex App/CLI 通过第三方模型提供商运行。

- Listen: `https://127.0.0.1:38443`
- Claude upstream: `https://ark.cn-beijing.volces.com/api/coding`
- Codex upstream: `https://ark.cn-beijing.volces.com/api/coding/v3/chat/completions`
- Health check: `https://127.0.0.1:38443/health`
- Dashboard: `https://127.0.0.1:38443/dashboard`
- Telemetry summary: `https://127.0.0.1:38443/telemetry/summary`
- Model mapping:
  - `claude-opus-4-6` / `opus` -> `glm-5.1`
  - `claude-sonnet-4-6` / `sonnet` -> `kimi-k2.6`
  - `claude-haiku-4-5` / `haiku` -> `doubao-seed-2.0-pro`

## Client source prefixes

为区分工具来源，客户端配置使用不同 base URL；代理会剥离前缀后再转发到上游。

| Client | Base URL |
| --- | --- |
| Claude Code Desktop | `https://127.0.0.1:38443/claude-desktop` |
| Claude Code CLI | `https://127.0.0.1:38443/claude-cli` |
| Codex App | `https://127.0.0.1:38443/codex-app/v1` |
| Codex CLI | `https://127.0.0.1:38443/codex-cli/v1` |

没有前缀的旧路径仍兼容，但 telemetry 会标记为 `claude_unknown` 或 `codex_unknown`。

## Telemetry

代理不保存 API key、prompt、response 文本、cookie 或 authorization。`logs/telemetry.jsonl` 只记录脱敏结构化指标：

```text
ts, tool, client, kind, method, path, client_model, upstream_model,
status, latency_ms, usage, error_type
```

`kind=count_tokens` 表示 Claude token count 请求；页面会单独显示请求记录，排查时不要把它简单等同于一次生成消费。

## Remote service

远端 Mac 当前服务由 LaunchAgent `com.cj.claude-local-https-proxy` 托管。已验证 `launchctl print` 中包含：

```text
properties = keepalive | runatload | inferred program
```

因此该代理在用户登录后会自动加载，并由 `KeepAlive` 保持运行。
