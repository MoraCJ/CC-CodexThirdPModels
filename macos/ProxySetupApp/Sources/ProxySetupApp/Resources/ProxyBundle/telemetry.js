'use strict';

const fs = require('fs');
const path = require('path');

const prefixMap = [
  { prefix: '/claude-desktop', client: 'claude_desktop', tool: 'claude' },
  { prefix: '/claude-cli', client: 'claude_cli', tool: 'claude' },
  { prefix: '/codex-app', client: 'codex_app', tool: 'codex' },
  { prefix: '/codex-cli', client: 'codex_cli', tool: 'codex' },
];

function classifyRequestUrl(requestUrl) {
  const url = new URL(requestUrl || '/', 'https://local.proxy');

  for (const item of prefixMap) {
    if (url.pathname === item.prefix || url.pathname.startsWith(`${item.prefix}/`)) {
      const strippedPath = url.pathname.slice(item.prefix.length) || '/';
      return {
        client: item.client,
        tool: item.tool,
        strippedUrl: `${strippedPath}${url.search}`,
        prefixed: true,
      };
    }
  }

  const tool = url.pathname.endsWith('/responses') ? 'codex' : 'claude';
  return {
    client: `${tool}_unknown`,
    tool,
    strippedUrl: `${url.pathname}${url.search}`,
    prefixed: false,
  };
}

function toNonNegativeNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : 0;
}

function normalizeUsage(usage) {
  if (!usage || typeof usage !== 'object') {
    return { input_tokens: 0, output_tokens: 0, total_tokens: 0 };
  }

  const inputTokens = toNonNegativeNumber(usage.input_tokens ?? usage.prompt_tokens);
  const outputTokens = toNonNegativeNumber(usage.output_tokens ?? usage.completion_tokens);
  const explicitTotal = toNonNegativeNumber(usage.total_tokens);

  return {
    input_tokens: inputTokens,
    output_tokens: outputTokens,
    total_tokens: explicitTotal || inputTokens + outputTokens,
  };
}

function createBucket() {
  return {
    requests: 0,
    failures: 0,
    input_tokens: 0,
    output_tokens: 0,
    total_tokens: 0,
    latency_ms_total: 0,
    latency_ms_avg: 0,
  };
}

function addEventToBucket(bucket, event) {
  const usage = normalizeUsage(event.usage);
  bucket.requests += 1;
  if (Number(event.status || 0) >= 400) bucket.failures += 1;
  bucket.input_tokens += usage.input_tokens;
  bucket.output_tokens += usage.output_tokens;
  bucket.total_tokens += usage.total_tokens;
  bucket.latency_ms_total += toNonNegativeNumber(event.latency_ms);
  bucket.latency_ms_avg = bucket.requests > 0 ? Math.round(bucket.latency_ms_total / bucket.requests) : 0;
}

function aggregateEvents(events) {
  const summary = {
    total: createBucket(),
    by_tool: {},
    by_client: {},
    by_model: {},
  };

  for (const event of events || []) {
    addEventToBucket(summary.total, event);

    const tool = event.tool || 'unknown';
    const client = event.client || 'unknown';
    const model = event.upstream_model || event.client_model || 'unknown';

    summary.by_tool[tool] ??= createBucket();
    summary.by_client[client] ??= createBucket();
    summary.by_model[model] ??= createBucket();

    addEventToBucket(summary.by_tool[tool], event);
    addEventToBucket(summary.by_client[client], event);
    addEventToBucket(summary.by_model[model], event);
  }

  return summary;
}

function ensureParentDir(file) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
}

function appendJsonlEvent(file, event) {
  ensureParentDir(file);
  fs.appendFileSync(file, `${JSON.stringify(event)}\n`);
}

function readJsonlEvents(file, limit = 1000) {
  if (!fs.existsSync(file)) return [];

  const lines = fs.readFileSync(file, 'utf8').trim().split('\n').filter(Boolean);
  const selected = limit > 0 ? lines.slice(-limit) : lines;
  const events = [];

  for (const line of selected) {
    try {
      events.push(JSON.parse(line));
    } catch {
      // Ignore malformed historical lines instead of breaking the dashboard.
    }
  }

  return events;
}

module.exports = {
  aggregateEvents,
  appendJsonlEvent,
  classifyRequestUrl,
  normalizeUsage,
  readJsonlEvents,
};
