# Proxy Usage Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-page local dashboard that separates Claude Code Desktop/CLI and Codex App/CLI model usage through the unified proxy.

**Architecture:** Keep the proxy as the single observation point. Add a small telemetry helper module for source classification, token usage normalization, JSONL event persistence, and dashboard aggregates. Keep prompt/response content and secrets out of telemetry.

**Tech Stack:** Node.js built-ins only: `https`, `fs`, `path`, `node:test`, `assert`.

---

### Task 1: Telemetry Helpers

**Files:**
- Create: `claude-local-proxy/tests/telemetry.test.js`
- Create: `claude-local-proxy/telemetry.js`

- [ ] Write Node tests for prefixed client detection, legacy fallback detection, usage normalization, and aggregate summaries.
- [ ] Run `node --test claude-local-proxy/tests/telemetry.test.js` and confirm it fails because `telemetry.js` is missing.
- [ ] Implement `telemetry.js` with no external dependencies.
- [ ] Run the test again and confirm it passes.

### Task 2: Proxy Integration

**Files:**
- Modify: `claude-local-proxy/server.js`

- [ ] Strip source prefixes before routing upstream:
  - `/claude-desktop`
  - `/claude-cli`
  - `/codex-app`
  - `/codex-cli`
- [ ] Record telemetry events for Claude and Codex requests after responses complete.
- [ ] Add local endpoints:
  - `/dashboard`
  - `/telemetry/summary`
  - `/telemetry/events`
- [ ] Keep `/health` and `/healthz` compatible.

### Task 3: Remote Deployment

**Files:**
- Remote backup: `/Users/corptest/Documents/Codex/claude-code-app-api/claude-local-proxy/server.js.bak.telemetry.<timestamp>`
- Remote backup: `/Users/corptest/Documents/Codex/claude-code-app-api/claude-local-proxy/telemetry.js.bak.<timestamp>` if present

- [ ] Copy `server.js` and `telemetry.js` to the remote Mac.
- [ ] Restart `com.cj.claude-local-https-proxy` with `launchctl kickstart -k`.
- [ ] Verify `/health`, `/healthz`, `/dashboard`, `/telemetry/summary`.
- [ ] Verify the LaunchAgent has automatic startup semantics using `RunAtLoad` or an equivalent loaded GUI LaunchAgent with `KeepAlive`.

### Task 4: Client Configuration Notes

**Files:**
- Modify: `claude-local-proxy/README.md`
- Modify: `handoff.md`
- Create: `AGENTS.md`

- [ ] Document the four client base URLs:
  - Claude Desktop: `https://127.0.0.1:38443/claude-desktop`
  - Claude CLI: `https://127.0.0.1:38443/claude-cli`
  - Codex App: `https://127.0.0.1:38443/codex-app/v1`
  - Codex CLI: `https://127.0.0.1:38443/codex-cli/v1`
- [ ] Document dashboard and telemetry files.
- [ ] Update handoff with deployment status, validation output, and automatic startup status.
- [ ] Write project `AGENTS.md` with operating rules and remote proxy notes.
