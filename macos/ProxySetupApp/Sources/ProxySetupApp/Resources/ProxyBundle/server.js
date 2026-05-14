#!/usr/bin/env node
'use strict';

const fs = require('fs');
const https = require('https');
const path = require('path');
const { URL } = require('url');
const {
  aggregateEvents,
  appendJsonlEvent,
  classifyRequestUrl,
  normalizeUsage,
  readJsonlEvents,
} = require('./telemetry');
const { createKeychainReader, providerAuthHeader } = require('./keychain');

const listenHost = process.env.LISTEN_HOST || '127.0.0.1';
const listenPort = Number(process.env.LISTEN_PORT || 38443);
const upstreamBase = new URL(
  process.env.UPSTREAM_BASE_URL || 'https://ark.cn-beijing.volces.com/api/coding'
);
const certFile = process.env.TLS_CERT_FILE || `${__dirname}/certs/server.crt`;
const keyFile = process.env.TLS_KEY_FILE || `${__dirname}/certs/server.key`;
const bigModel = process.env.BIG_MODEL || 'glm-5.1';
const middleModel = process.env.MIDDLE_MODEL || 'kimi-k2.6';
const smallModel = process.env.SMALL_MODEL || 'doubao-seed-2.0-pro';
const codexUpstreamBase = new URL(
  process.env.CODEX_UPSTREAM_BASE_URL || 'https://ark.cn-beijing.volces.com/api/coding/v3'
);
const codexDefaultModel = process.env.CODEX_DEFAULT_MODEL || smallModel;
const telemetryFile = process.env.TELEMETRY_FILE || path.join(__dirname, 'logs', 'telemetry.jsonl');
const telemetryReadLimit = Number(process.env.TELEMETRY_READ_LIMIT || 5000);
const telemetryCaptureBytes = Number(process.env.TELEMETRY_CAPTURE_BYTES || 2 * 1024 * 1024);
const keychainReader = createKeychainReader();
const keychainService = process.env.KEYCHAIN_SERVICE || 'CJLocalProxy';
const claudeKeychainAccount = process.env.CLAUDE_KEYCHAIN_ACCOUNT || 'claude-upstream-api-key';
const codexKeychainAccount = process.env.CODEX_KEYCHAIN_ACCOUNT || 'codex-upstream-api-key';

const hopByHopHeaders = new Set([
  'connection',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
]);

function scrubHeaders(headers) {
  const next = {};
  for (const [name, value] of Object.entries(headers)) {
    const lower = name.toLowerCase();
    if (hopByHopHeaders.has(lower)) continue;
    if (lower === 'authorization') continue;
    if (lower === 'host') continue;
    next[name] = value;
  }
  next.host = upstreamBase.host;
  next['x-forwarded-host'] = headers.host || `${listenHost}:${listenPort}`;
  next['x-forwarded-proto'] = 'https';
  return next;
}

function targetFor(requestUrl) {
  const target = new URL(requestUrl, upstreamBase.origin);
  target.pathname = requestUrl.startsWith(upstreamBase.pathname)
    ? new URL(requestUrl, upstreamBase.origin).pathname
    : `${upstreamBase.pathname.replace(/\/$/, '')}${target.pathname}`;
  return target;
}

async function upstreamAuthorization(tool) {
  if (tool === 'codex') {
    return providerAuthHeader({
      reader: keychainReader,
      service: keychainService,
      account: codexKeychainAccount,
      fallback: process.env.CODEX_UPSTREAM_API_KEY || process.env.OPENAI_API_KEY || process.env.ARK_API_KEY,
    });
  }

  return providerAuthHeader({
    reader: keychainReader,
    service: keychainService,
    account: claudeKeychainAccount,
    fallback: process.env.CLAUDE_UPSTREAM_API_KEY || process.env.ANTHROPIC_AUTH_TOKEN || process.env.ARK_API_KEY,
  });
}

function mappedModel(model) {
  if (typeof model !== 'string') return model;

  const modelWithoutContextSuffix = model.replace(/\[[^\]]+\]$/, '');
  const normalized = modelWithoutContextSuffix.toLowerCase();
  if (normalized.includes('haiku')) return smallModel;
  if (normalized.includes('opus')) return bigModel;
  if (normalized.includes('sonnet') || normalized.includes('claude')) return middleModel;

  return modelWithoutContextSuffix;
}

function requestKind(requestUrl) {
  const pathname = new URL(requestUrl || '/', 'https://local.proxy').pathname;
  if (pathname.includes('/count_tokens')) return 'count_tokens';
  if (pathname.endsWith('/messages') || pathname.endsWith('/responses')) return 'generation';
  return 'other';
}

function looksLikeUsage(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  return (
    value.input_tokens !== undefined ||
    value.output_tokens !== undefined ||
    value.prompt_tokens !== undefined ||
    value.completion_tokens !== undefined ||
    value.total_tokens !== undefined
  );
}

function findUsage(value, depth = 0) {
  if (!value || typeof value !== 'object' || depth > 8) return null;
  if (looksLikeUsage(value)) return value;
  if (looksLikeUsage(value.usage)) return value.usage;

  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findUsage(item, depth + 1);
      if (found) return found;
    }
    return null;
  }

  for (const item of Object.values(value)) {
    const found = findUsage(item, depth + 1);
    if (found) return found;
  }
  return null;
}

function extractUsageFromText(text) {
  if (!text) return normalizeUsage(null);

  try {
    const json = JSON.parse(text);
    return normalizeUsage(findUsage(json));
  } catch {
    // Continue with SSE parsing below.
  }

  let usage = null;
  for (const line of text.split(/\r?\n/)) {
    if (!line.startsWith('data:')) continue;
    const data = line.slice(5).trim();
    if (!data || data === '[DONE]') continue;
    try {
      const parsed = JSON.parse(data);
      usage = findUsage(parsed) || usage;
    } catch {
      // Ignore non-JSON SSE data lines.
    }
  }

  return normalizeUsage(usage);
}

function recordTelemetry(event) {
  try {
    appendJsonlEvent(telemetryFile, {
      ts: new Date().toISOString(),
      tool: event.tool || 'unknown',
      client: event.client || 'unknown',
      kind: event.kind || 'other',
      method: event.method || '',
      path: event.path || '',
      client_model: event.client_model || '',
      upstream_model: event.upstream_model || '',
      status: Number(event.status || 0),
      latency_ms: Number(event.latency_ms || 0),
      usage: normalizeUsage(event.usage),
      error_type: event.error_type || '',
    });
  } catch (error) {
    console.error(`${new Date().toISOString()} telemetry write error: ${error.stack || error.message}`);
  }
}

function telemetrySnapshot(limit = telemetryReadLimit) {
  const events = readJsonlEvents(telemetryFile, limit);
  return {
    generated_at: new Date().toISOString(),
    telemetry_file: telemetryFile,
    summary: aggregateEvents(events),
    recent: events.slice(-100).reverse(),
  };
}

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function formatNumber(value) {
  return new Intl.NumberFormat('en-US').format(Number(value || 0));
}

function displayName(value) {
  const names = {
    claude: 'Claude / Claude',
    codex: 'Codex / Codex',
    claude_desktop: 'Claude Desktop / Claude 桌面端',
    claude_cli: 'Claude CLI / Claude 命令行',
    claude_unknown: 'Claude Unknown / Claude 未识别',
    codex_app: 'Codex App / Codex 桌面端',
    codex_cli: 'Codex CLI / Codex 命令行',
    codex_unknown: 'Codex Unknown / Codex 未识别',
    generation: 'Generation / 生成',
    count_tokens: 'Count Tokens / 计数',
    other: 'Other / 其他',
    unknown: 'Unknown / 未识别',
  };
  return names[value] || value || names.unknown;
}

function statusClass(status) {
  const code = Number(status || 0);
  if (code >= 500) return 'status status-error';
  if (code >= 400) return 'status status-warn';
  if (code >= 200) return 'status status-ok';
  return 'status';
}

function renderBucketRows(buckets, emptyLabel = 'No data / 暂无数据') {
  const entries = Object.entries(buckets)
    .sort(([, a], [, b]) => b.requests - a.requests)
    .map(([name, bucket]) => {
      const failureRate = bucket.requests > 0 ? Math.round((bucket.failures / bucket.requests) * 100) : 0;
      return `
        <tr>
          <td><span class="name">${escapeHtml(displayName(name))}</span><code>${escapeHtml(name)}</code></td>
          <td>${formatNumber(bucket.requests)}</td>
          <td>${formatNumber(bucket.failures)} <span class="subtle">(${failureRate}%)</span></td>
          <td>${formatNumber(bucket.input_tokens)}</td>
          <td>${formatNumber(bucket.output_tokens)}</td>
          <td>${formatNumber(bucket.total_tokens)}</td>
          <td>${formatNumber(bucket.latency_ms_avg)}ms</td>
        </tr>`;
    });

  if (entries.length === 0) {
    return `<tr><td class="empty" colspan="7">${escapeHtml(emptyLabel)}</td></tr>`;
  }

  return entries.join('');
}

function renderDashboard() {
  const snapshot = telemetrySnapshot();
  const { summary, recent } = snapshot;
  const recentRows = recent
    .map(
      (event) => `
        <tr>
          <td>${escapeHtml(event.ts)}</td>
          <td><span class="name">${escapeHtml(displayName(event.client))}</span><code>${escapeHtml(event.client)}</code></td>
          <td>${escapeHtml(displayName(event.kind))}</td>
          <td><code>${escapeHtml(event.upstream_model || event.client_model || 'unknown')}</code></td>
          <td><span class="${statusClass(event.status)}">${escapeHtml(event.status)}</span></td>
          <td>${formatNumber(event.usage?.total_tokens)}</td>
          <td>${formatNumber(event.latency_ms)}ms</td>
          <td>${escapeHtml(event.path)}</td>
        </tr>`
    )
    .join('') || '<tr><td class="empty" colspan="8">No requests yet / 暂无请求记录</td></tr>';

  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Proxy Usage Dashboard / 代理用量看板</title>
  <style>
    :root {
      color-scheme: light;
      font-family: Inter, ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      --bg: #f4f6f8;
      --surface: #ffffff;
      --surface-soft: #f9fafb;
      --ink: #17202a;
      --muted: #637083;
      --line: #dde4ec;
      --line-soft: #edf1f5;
      --accent: #0f766e;
      --accent-soft: #dff7f3;
      --blue: #2563eb;
      --amber: #b45309;
      --red: #b42318;
      --shadow: 0 14px 40px rgba(31, 42, 55, .08);
    }
    * { box-sizing: border-box; }
    body { margin: 0; background: var(--bg); color: var(--ink); }
    .shell { max-width: 1480px; margin: 0 auto; padding: 24px 28px 34px; }
    .topbar {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: 20px;
      padding: 22px 24px;
      background: linear-gradient(135deg, #ffffff 0%, #f8fbfc 68%, #eef8f6 100%);
      border: 1px solid var(--line);
      border-radius: 8px;
      box-shadow: var(--shadow);
    }
    h1 { margin: 0; font-size: 30px; line-height: 1.15; letter-spacing: 0; }
    h1 span { display: block; margin-top: 5px; color: var(--muted); font-size: 15px; font-weight: 600; }
    h2 { margin: 0; font-size: 16px; line-height: 1.3; letter-spacing: 0; }
    h2 span { color: var(--muted); font-size: 13px; font-weight: 500; }
    .meta { display: grid; gap: 6px; color: var(--muted); font-size: 12px; text-align: right; }
    .meta a {
      color: var(--accent);
      text-decoration: none;
      font-weight: 700;
    }
    .stats {
      display: grid;
      grid-template-columns: repeat(5, minmax(150px, 1fr));
      gap: 12px;
      margin-top: 16px;
    }
    .stat {
      min-height: 112px;
      padding: 16px;
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 8px;
      box-shadow: 0 4px 18px rgba(31, 42, 55, .04);
    }
    .stat span { display: block; color: var(--muted); font-size: 12px; font-weight: 700; text-transform: uppercase; }
    .stat em { display: block; margin-top: 2px; color: var(--muted); font-size: 12px; font-style: normal; }
    .stat strong { display: block; margin-top: 18px; color: var(--ink); font-size: 28px; line-height: 1; letter-spacing: 0; }
    .legend {
      display: grid;
      grid-template-columns: repeat(4, minmax(180px, 1fr));
      gap: 10px;
      margin-top: 16px;
    }
    .legend-item {
      padding: 10px 12px;
      background: #eef8f6;
      border: 1px solid #c7e7e1;
      border-radius: 8px;
      color: #14534c;
      font-size: 12px;
      font-weight: 700;
    }
    .legend-item code { display: block; margin-top: 4px; color: #245f58; font-weight: 600; }
    .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-top: 18px; }
    .panel { margin-top: 18px; }
    .panel-head { display: flex; justify-content: space-between; align-items: baseline; gap: 12px; margin-bottom: 9px; }
    section {
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 8px;
      overflow: hidden;
      box-shadow: 0 6px 24px rgba(31, 42, 55, .05);
    }
    .table-wrap { overflow-x: auto; }
    table { width: 100%; border-collapse: collapse; font-size: 13px; }
    th, td { border-bottom: 1px solid var(--line-soft); padding: 11px 12px; text-align: right; white-space: nowrap; }
    tr:last-child td { border-bottom: 0; }
    th:first-child, td:first-child, td:nth-child(8) { text-align: left; }
    th {
      color: #536173;
      font-size: 11px;
      font-weight: 800;
      text-transform: uppercase;
      background: var(--surface-soft);
      border-bottom-color: var(--line);
    }
    td { color: #1d2733; }
    code {
      display: inline-block;
      margin-top: 3px;
      color: #5c6878;
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-size: 11px;
      background: #f1f4f7;
      border: 1px solid #e4e9ef;
      border-radius: 6px;
      padding: 2px 6px;
    }
    .name { display: block; color: var(--ink); font-weight: 700; }
    .subtle { color: var(--muted); }
    .empty { color: var(--muted); text-align: center !important; padding: 22px 12px; }
    .status {
      display: inline-flex;
      min-width: 44px;
      justify-content: center;
      padding: 3px 8px;
      border-radius: 999px;
      font-weight: 800;
      background: #eef2f6;
      color: #536173;
    }
    .status-ok { background: #e3f8ef; color: #087443; }
    .status-warn { background: #fff3d6; color: var(--amber); }
    .status-error { background: #ffe4df; color: var(--red); }
    @media (max-width: 980px) {
      .shell { padding: 16px; }
      .topbar { flex-direction: column; }
      .meta { text-align: left; }
      .stats, .legend, .grid { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <div class="shell">
  <header class="topbar">
    <div>
      <h1>Proxy Usage Dashboard<span>代理用量看板</span></h1>
    </div>
    <div class="meta">
      <div>Updated / 更新时间：${escapeHtml(snapshot.generated_at)}</div>
      <div>Telemetry / 指标文件：${escapeHtml(snapshot.telemetry_file)}</div>
      <div><a href="/telemetry/summary">JSON Summary / 汇总数据</a></div>
    </div>
  </header>
    <div class="stats">
      <div class="stat"><span>Requests</span><em>请求数</em><strong>${formatNumber(summary.total.requests)}</strong></div>
      <div class="stat"><span>Failures</span><em>失败数</em><strong>${formatNumber(summary.total.failures)}</strong></div>
      <div class="stat"><span>Input Tokens</span><em>输入 tokens</em><strong>${formatNumber(summary.total.input_tokens)}</strong></div>
      <div class="stat"><span>Output Tokens</span><em>输出 tokens</em><strong>${formatNumber(summary.total.output_tokens)}</strong></div>
      <div class="stat"><span>Total Tokens</span><em>总 tokens</em><strong>${formatNumber(summary.total.total_tokens)}</strong></div>
    </div>
    <div class="legend">
      <div class="legend-item">Claude Desktop / Claude 桌面端<code>/claude-desktop</code></div>
      <div class="legend-item">Claude CLI / Claude 命令行<code>/claude-cli</code></div>
      <div class="legend-item">Codex App / Codex 桌面端<code>/codex-app/v1</code></div>
      <div class="legend-item">Codex CLI / Codex 命令行<code>/codex-cli/v1</code></div>
    </div>
  <main>
    <div class="grid">
      <div class="panel">
        <div class="panel-head"><h2>By Client <span>/ 按客户端</span></h2></div>
        <section><div class="table-wrap"><table><thead><tr><th>Client / 客户端</th><th>Requests / 请求</th><th>Failures / 失败</th><th>Input / 输入</th><th>Output / 输出</th><th>Total / 总计</th><th>Avg Latency / 平均耗时</th></tr></thead><tbody>${renderBucketRows(summary.by_client)}</tbody></table></div></section>
      </div>
      <div class="panel">
        <div class="panel-head"><h2>By Tool <span>/ 按工具</span></h2></div>
        <section><div class="table-wrap"><table><thead><tr><th>Tool / 工具</th><th>Requests / 请求</th><th>Failures / 失败</th><th>Input / 输入</th><th>Output / 输出</th><th>Total / 总计</th><th>Avg Latency / 平均耗时</th></tr></thead><tbody>${renderBucketRows(summary.by_tool)}</tbody></table></div></section>
      </div>
    </div>
    <div class="panel">
      <div class="panel-head"><h2>By Model <span>/ 按模型</span></h2></div>
      <section><div class="table-wrap"><table><thead><tr><th>Model / 模型</th><th>Requests / 请求</th><th>Failures / 失败</th><th>Input / 输入</th><th>Output / 输出</th><th>Total / 总计</th><th>Avg Latency / 平均耗时</th></tr></thead><tbody>${renderBucketRows(summary.by_model)}</tbody></table></div></section>
    </div>
    <div class="panel">
      <div class="panel-head"><h2>Recent Requests <span>/ 最近请求</span></h2></div>
      <section><div class="table-wrap"><table><thead><tr><th>Time / 时间</th><th>Client / 客户端</th><th>Kind / 类型</th><th>Model / 模型</th><th>Status / 状态</th><th>Tokens / tokens</th><th>Latency / 耗时</th><th>Path / 路径</th></tr></thead><tbody>${recentRows}</tbody></table></div></section>
    </div>
  </main>
  </div>
</body>
</html>`;
}

function readRequestBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

async function bodyForUpstream(req) {
  const body = await readRequestBody(req);
  const result = {
    body,
    clientModel: '',
    upstreamModel: '',
  };
  if (body.length === 0) return result;

  try {
    const payload = JSON.parse(body.toString('utf8'));
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return result;

    const originalModel = payload.model;
    const nextModel = mappedModel(originalModel);
    result.clientModel = typeof originalModel === 'string' ? originalModel : '';
    result.upstreamModel = typeof nextModel === 'string' ? nextModel : result.clientModel;
    if (typeof originalModel === 'string') {
      console.log(`${new Date().toISOString()} request model ${originalModel}`);
    }
    if (nextModel === originalModel) return result;

    payload.model = nextModel;
    console.log(`${new Date().toISOString()} mapped model ${originalModel} -> ${nextModel}`);
    result.body = Buffer.from(JSON.stringify(payload));
    return result;
  } catch {
    return result;
  }
}

function textFromResponsesContent(content) {
  if (content == null) return '';
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) {
    if (typeof content.text === 'string') return content.text;
    if (typeof content.output === 'string') return content.output;
    return JSON.stringify(content);
  }

  return content
    .map((part) => {
      if (typeof part === 'string') return part;
      if (!part || typeof part !== 'object') return '';
      if (typeof part.text === 'string') return part.text;
      if (typeof part.output === 'string') return part.output;
      if (part.type === 'input_image' || part.type === 'image_url') return '[image]';
      return '';
    })
    .filter(Boolean)
    .join('\n');
}

function responsesInputToChatMessages(input, instructions) {
  const messages = [];
  if (instructions) messages.push({ role: 'system', content: String(instructions) });

  const append = (item) => {
    if (typeof item === 'string') {
      messages.push({ role: 'user', content: item });
      return;
    }
    if (!item || typeof item !== 'object') return;

    if (item.type === 'function_call_output') {
      messages.push({
        role: 'tool',
        tool_call_id: item.call_id || item.id || 'call_unknown',
        content: typeof item.output === 'string' ? item.output : JSON.stringify(item.output ?? ''),
      });
      return;
    }

    if (item.type === 'function_call') {
      messages.push({
        role: 'assistant',
        content: null,
        tool_calls: [
          {
            id: item.call_id || item.id || `call_${Date.now()}`,
            type: 'function',
            function: {
              name: item.name,
              arguments: typeof item.arguments === 'string' ? item.arguments : JSON.stringify(item.arguments ?? {}),
            },
          },
        ],
      });
      return;
    }

    const role = item.role === 'assistant' || item.role === 'system' || item.role === 'developer' ? item.role : 'user';
    const chatRole = role === 'developer' ? 'system' : role;
    const content = textFromResponsesContent(item.content ?? item.text ?? item.input);
    if (content) messages.push({ role: chatRole, content });
  };

  if (Array.isArray(input)) input.forEach(append);
  else append(input);

  if (messages.length === 0) messages.push({ role: 'user', content: '' });
  return messages;
}

function responsesToolsToChatTools(tools) {
  if (!Array.isArray(tools)) return undefined;

  const converted = [];
  for (const tool of tools) {
    if (!tool || typeof tool !== 'object') continue;
    if (tool.type !== 'function' || !tool.name) continue;
    converted.push({
      type: 'function',
      function: {
        name: tool.name,
        description: tool.description || '',
        parameters: tool.parameters || { type: 'object', properties: {} },
      },
    });
  }

  return converted.length > 0 ? converted : undefined;
}

function buildCodexChatRequest(body) {
  const request = {
    model: mappedModel(body.model || codexDefaultModel),
    messages: responsesInputToChatMessages(body.input, body.instructions),
    stream: false,
  };

  const tools = responsesToolsToChatTools(body.tools);
  if (tools) {
    request.tools = tools;
    if (body.parallel_tool_calls !== undefined) request.parallel_tool_calls = body.parallel_tool_calls;
    if (body.tool_choice && body.tool_choice !== 'auto') request.tool_choice = body.tool_choice;
  }

  if (typeof body.temperature === 'number') request.temperature = body.temperature;
  if (typeof body.top_p === 'number') request.top_p = body.top_p;
  if (typeof body.max_output_tokens === 'number') request.max_tokens = body.max_output_tokens;
  if (body.metadata) request.metadata = body.metadata;
  return request;
}

async function callCodexChatCompletions(chatRequest, authorization) {
  const target = new URL(`${codexUpstreamBase.pathname.replace(/\/$/, '')}/chat/completions`, codexUpstreamBase.origin);

  const headers = {
    'content-type': 'application/json',
  };
  if (authorization) headers.authorization = authorization;

  const response = await fetch(target, {
    method: 'POST',
    headers,
    body: JSON.stringify(chatRequest),
  });
  const text = await response.text();
  if (!response.ok) {
    const error = new Error(`upstream ${response.status}: ${text.slice(0, 1000)}`);
    error.status = response.status;
    throw error;
  }
  return JSON.parse(text);
}

function createResponseBase(model) {
  return {
    id: `resp_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`,
    object: 'response',
    created_at: Math.floor(Date.now() / 1000),
    status: 'completed',
    model,
    output: [],
  };
}

function chatCompletionToResponses(chat, model) {
  const response = createResponseBase(model);
  const message = chat.choices?.[0]?.message || {};

  if (message.content) {
    response.output.push({
      id: `msg_${Date.now().toString(36)}`,
      type: 'message',
      status: 'completed',
      role: 'assistant',
      content: [{ type: 'output_text', text: String(message.content), annotations: [] }],
    });
  }

  for (const call of message.tool_calls || []) {
    response.output.push({
      id: `fc_${Math.random().toString(36).slice(2, 10)}`,
      type: 'function_call',
      status: 'completed',
      call_id: call.id,
      name: call.function?.name || '',
      arguments: call.function?.arguments || '{}',
    });
  }

  if (chat.usage) {
    response.usage = {
      input_tokens: chat.usage.prompt_tokens || 0,
      output_tokens: chat.usage.completion_tokens || 0,
      total_tokens: chat.usage.total_tokens || 0,
    };
  }

  return response;
}

function writeResponsesSse(res, event, data) {
  res.write(`event: ${event}\n`);
  res.write(`data: ${JSON.stringify({ type: event, ...data })}\n\n`);
}

function sendResponsesSse(res, response) {
  res.writeHead(200, {
    'content-type': 'text/event-stream; charset=utf-8',
    'cache-control': 'no-cache, no-transform',
    connection: 'keep-alive',
  });

  writeResponsesSse(res, 'response.created', { response: { ...response, status: 'in_progress', output: [] } });
  response.output.forEach((item, outputIndex) => {
    if (item.type === 'message') {
      const text = item.content?.[0]?.text || '';
      const inProgress = { ...item, status: 'in_progress', content: [] };
      writeResponsesSse(res, 'response.output_item.added', { output_index: outputIndex, item: inProgress });
      writeResponsesSse(res, 'response.content_part.added', {
        output_index: outputIndex,
        item_id: item.id,
        content_index: 0,
        part: { type: 'output_text', text: '', annotations: [] },
      });
      if (text) {
        writeResponsesSse(res, 'response.output_text.delta', {
          output_index: outputIndex,
          item_id: item.id,
          content_index: 0,
          delta: text,
        });
      }
      writeResponsesSse(res, 'response.output_text.done', {
        output_index: outputIndex,
        item_id: item.id,
        content_index: 0,
        text,
      });
      writeResponsesSse(res, 'response.content_part.done', {
        output_index: outputIndex,
        item_id: item.id,
        content_index: 0,
        part: item.content[0],
      });
      writeResponsesSse(res, 'response.output_item.done', { output_index: outputIndex, item });
      return;
    }

    if (item.type === 'function_call') {
      const started = { ...item, status: 'in_progress', arguments: '' };
      writeResponsesSse(res, 'response.output_item.added', { output_index: outputIndex, item: started });
      if (item.arguments) {
        writeResponsesSse(res, 'response.function_call_arguments.delta', {
          output_index: outputIndex,
          item_id: item.id,
          delta: item.arguments,
        });
      }
      writeResponsesSse(res, 'response.function_call_arguments.done', {
        output_index: outputIndex,
        item_id: item.id,
        arguments: item.arguments,
      });
      writeResponsesSse(res, 'response.output_item.done', { output_index: outputIndex, item });
    }
  });
  writeResponsesSse(res, 'response.completed', { response });
  res.write('data: [DONE]\n\n');
  res.end();
}

async function handleCodexResponses(req, res, source, requestUrl) {
  const started = Date.now();
  let body;
  try {
    const rawBody = await readRequestBody(req);
    body = JSON.parse(rawBody.toString('utf8') || '{}');
  } catch (error) {
    res.writeHead(400, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: { type: 'request_body_error', message: error.message } }));
    recordTelemetry({
      ...source,
      kind: requestKind(requestUrl),
      method: req.method,
      path: requestUrl,
      status: 400,
      latency_ms: Date.now() - started,
      error_type: 'request_body_error',
    });
    return;
  }

  try {
    const chatRequest = buildCodexChatRequest(body);
    console.log(
      `${new Date().toISOString()} codex responses model ${body.model || codexDefaultModel} -> ${chatRequest.model}`
    );
    const authorization = await upstreamAuthorization('codex');
    const chat = await callCodexChatCompletions(chatRequest, authorization);
    const response = chatCompletionToResponses(chat, chatRequest.model);
    const ms = Date.now() - started;
    console.log(`${new Date().toISOString()} ${req.method} ${req.url} -> codex responses 200 ${ms}ms`);
    recordTelemetry({
      ...source,
      kind: requestKind(requestUrl),
      method: req.method,
      path: requestUrl,
      client_model: body.model || codexDefaultModel,
      upstream_model: chatRequest.model,
      status: 200,
      latency_ms: ms,
      usage: response.usage,
    });

    if (body.stream === false) {
      res.writeHead(200, { 'content-type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify(response));
      return;
    }

    sendResponsesSse(res, response);
  } catch (error) {
    const status = error.status || 502;
    if (!res.headersSent) {
      res.writeHead(status, { 'content-type': 'application/json' });
    }
    res.end(JSON.stringify({ error: { type: 'codex_proxy_error', message: error.message } }));
    recordTelemetry({
      ...source,
      kind: requestKind(requestUrl),
      method: req.method,
      path: requestUrl,
      client_model: body?.model || codexDefaultModel,
      upstream_model: body ? mappedModel(body.model || codexDefaultModel) : '',
      status,
      latency_ms: Date.now() - started,
      error_type: 'codex_proxy_error',
    });
    console.error(`${new Date().toISOString()} codex proxy error ${req.method} ${req.url}: ${error.stack || error.message}`);
  }
}

const server = https.createServer(
  {
    cert: fs.readFileSync(certFile),
    key: fs.readFileSync(keyFile),
  },
  async (req, res) => {
    const source = classifyRequestUrl(req.url || '/');
    const requestUrl = source.strippedUrl;

    if (requestUrl === '/health') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(
        JSON.stringify({
          ok: true,
          upstream: upstreamBase.href,
          codexUpstream: codexUpstreamBase.href,
          bigModel,
          middleModel,
          smallModel,
          telemetryFile,
          dashboard: '/dashboard',
          clientPrefixes: {
            claudeDesktop: '/claude-desktop',
            claudeCli: '/claude-cli',
            codexApp: '/codex-app/v1',
            codexCli: '/codex-cli/v1',
          },
        })
      );
      return;
    }

    if (requestUrl === '/healthz') {
      res.writeHead(200, { 'content-type': 'text/plain' });
      res.end('ok\n');
      return;
    }

    if (requestUrl === '/dashboard') {
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      res.end(renderDashboard());
      return;
    }

    if (requestUrl === '/telemetry/summary') {
      res.writeHead(200, { 'content-type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify(telemetrySnapshot()));
      return;
    }

    if (requestUrl === '/telemetry/events') {
      const events = readJsonlEvents(telemetryFile, telemetryReadLimit).slice(-500).reverse();
      res.writeHead(200, { 'content-type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ generated_at: new Date().toISOString(), events }));
      return;
    }

    const pathname = new URL(requestUrl || '/', `https://${req.headers.host || `${listenHost}:${listenPort}`}`).pathname;
    if (req.method === 'POST' && pathname.endsWith('/responses')) {
      await handleCodexResponses(req, res, source, requestUrl);
      return;
    }

    const target = targetFor(requestUrl || '/');
    const started = Date.now();
    let upstream;
    try {
      upstream = await bodyForUpstream(req);
    } catch (error) {
      res.writeHead(400, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: 'request_body_error', message: error.message }));
      recordTelemetry({
        ...source,
        kind: requestKind(requestUrl),
        method: req.method,
        path: requestUrl,
        status: 400,
        latency_ms: Date.now() - started,
        error_type: 'request_body_error',
      });
      return;
    }
    const headers = scrubHeaders(req.headers);
    const authorization = await upstreamAuthorization('claude');
    if (authorization) headers.authorization = authorization;
    headers['content-length'] = String(upstream.body.length);

    const proxyReq = https.request(
      {
        protocol: target.protocol,
        hostname: target.hostname,
        port: target.port || 443,
        method: req.method,
        path: `${target.pathname}${target.search}`,
        headers,
        timeout: Number(process.env.UPSTREAM_TIMEOUT_MS || 300000),
      },
      (proxyRes) => {
        const headers = { ...proxyRes.headers };
        delete headers.connection;
        delete headers['transfer-encoding'];
        res.writeHead(proxyRes.statusCode || 502, headers);
        const chunks = [];
        let capturedBytes = 0;
        proxyRes.on('data', (chunk) => {
          if (capturedBytes < telemetryCaptureBytes) {
            const remaining = telemetryCaptureBytes - capturedBytes;
            const captured = chunk.length > remaining ? chunk.subarray(0, remaining) : chunk;
            chunks.push(captured);
            capturedBytes += captured.length;
          }
        });
        proxyRes.pipe(res);
        proxyRes.on('end', () => {
          const ms = Date.now() - started;
          console.log(`${new Date().toISOString()} ${req.method} ${req.url} -> ${proxyRes.statusCode} ${ms}ms`);
          const usage = extractUsageFromText(Buffer.concat(chunks).toString('utf8'));
          recordTelemetry({
            ...source,
            kind: requestKind(requestUrl),
            method: req.method,
            path: requestUrl,
            client_model: upstream.clientModel,
            upstream_model: upstream.upstreamModel,
            status: proxyRes.statusCode || 502,
            latency_ms: ms,
            usage,
          });
        });
      }
    );

    proxyReq.on('timeout', () => {
      proxyReq.destroy(new Error('upstream timeout'));
    });

    proxyReq.on('error', (error) => {
      if (!res.headersSent) {
        res.writeHead(502, { 'content-type': 'application/json' });
      }
      res.end(JSON.stringify({ error: 'proxy_error', message: error.message }));
      recordTelemetry({
        ...source,
        kind: requestKind(requestUrl),
        method: req.method,
        path: requestUrl,
        client_model: upstream?.clientModel,
        upstream_model: upstream?.upstreamModel,
        status: 502,
        latency_ms: Date.now() - started,
        error_type: 'proxy_error',
      });
      console.error(`${new Date().toISOString()} proxy error ${req.method} ${req.url}: ${error.stack || error.message}`);
    });

    proxyReq.end(upstream.body);
  }
);

server.keepAliveTimeout = Number(process.env.KEEP_ALIVE_TIMEOUT_MS || 300000);
server.headersTimeout = Number(process.env.HEADERS_TIMEOUT_MS || 310000);
server.requestTimeout = Number(process.env.REQUEST_TIMEOUT_MS || 0);

server.listen(listenPort, listenHost, () => {
  console.log(`${new Date().toISOString()} Claude local HTTPS proxy listening on https://${listenHost}:${listenPort}`);
  console.log(`${new Date().toISOString()} Upstream base: ${upstreamBase.href}`);
  console.log(`${new Date().toISOString()} Codex upstream base: ${codexUpstreamBase.href}`);
  console.log(`${new Date().toISOString()} Model mapping: opus=${bigModel}, sonnet=${middleModel}, haiku=${smallModel}`);
});
