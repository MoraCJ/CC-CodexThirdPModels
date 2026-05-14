# AGENTS.md

你的名字叫棒槌，老板是 CJ。默认使用简体中文回复，专业词汇可保留英文。

## 项目目标

本项目维护 Claude Code Desktop/CLI 与 Codex App/CLI 通过本机 HTTPS 统一代理访问第三方模型提供商的材料、代理代码、配置说明和交接文档。

新增或更新项目文档、spec、handoff、runbook 时默认使用简体中文。专业词汇可以保留英文，例如 API、Base URL、Keychain、LaunchAgent、Telemetry。

## 当前关键架构

- 远端 Mac：`172.16.66.188`，用户：`corptest`。
- 远端项目目录：`/Users/corptest/Documents/Codex/claude-code-app-api`。
- 统一代理入口：`https://127.0.0.1:38443`。
- 代理服务：`claude-local-proxy/server.js`。
- LaunchAgent：`~/Library/LaunchAgents/com.cj.claude-local-https-proxy.plist`。
- Dashboard：`https://127.0.0.1:38443/dashboard`。
- Telemetry：`claude-local-proxy/logs/telemetry.jsonl`。
- GitHub 仓库：`https://github.com/MoraCJ/CC-CodexThirdPModels`。
- macOS 本机设置 App 设计文档：`docs/superpowers/specs/2026-05-14-macos-local-proxy-setup-app-design.md`。

## 客户端来源区分

必须保留以下四个 base URL，用于 dashboard 按客户端区分用量：

| 客户端 | Base URL |
| --- | --- |
| Claude Code Desktop | `https://127.0.0.1:38443/claude-desktop` |
| Claude Code CLI | `https://127.0.0.1:38443/claude-cli` |
| Codex App | `https://127.0.0.1:38443/codex-app/v1` |
| Codex CLI | `https://127.0.0.1:38443/codex-cli/v1` |

无前缀旧路径仍兼容，但只能落到 `claude_unknown` 或 `codex_unknown`，不应作为长期配置。

## 安全边界

- 不要在文档、代码、handoff 或日志摘录中写真实 API key、token、SSH 密码或私钥内容。
- 不要提交或公开 `certs/*.key`、`logs/*.log`、`logs/*.jsonl`。
- Telemetry 只允许记录结构化指标：时间、工具、客户端、模型、状态码、耗时、token usage、错误类型。
- 不记录 prompt、response 正文、Authorization、Cookie。

## 操作规则

- 修改远端前先备份，备份文件名包含时间戳。
- 修改代理后至少运行：
  - `node --check claude-local-proxy/server.js`
  - `node --check claude-local-proxy/telemetry.js`
  - `curl -sk https://127.0.0.1:38443/health`
  - `curl -sk https://127.0.0.1:38443/dashboard`
  - `curl -sk https://127.0.0.1:38443/telemetry/summary`
- 检查自动启动时看：
  - `launchctl print gui/$(id -u)/com.cj.claude-local-https-proxy`
  - 关键字段应包含 `state = running` 和 `properties = keepalive | runatload`。
- 如果要区分 Claude Desktop host 与 CLI，注意 Desktop 版本目录里的 `claude` 当前软链到 `claude-local-proxy/bin/claude-ca-launcher`；launcher 会注入 `ANTHROPIC_BASE_URL=https://127.0.0.1:38443/claude-desktop`。

## 常用命令

```bash
launchctl print gui/$(id -u)/com.cj.claude-local-https-proxy
launchctl kickstart -k gui/$(id -u)/com.cj.claude-local-https-proxy
curl -sk https://127.0.0.1:38443/health
curl -sk https://127.0.0.1:38443/telemetry/summary
tail -n 120 claude-local-proxy/logs/proxy.log
tail -n 120 claude-local-proxy/logs/proxy.err.log
```
