'use strict';

const assert = require('assert/strict');
const test = require('node:test');

const {
  aggregateEvents,
  classifyRequestUrl,
  normalizeUsage,
} = require('../telemetry');

test('classifies explicit client prefixes and strips them from upstream URLs', () => {
  assert.deepEqual(classifyRequestUrl('/claude-desktop/v1/messages?beta=true'), {
    client: 'claude_desktop',
    tool: 'claude',
    strippedUrl: '/v1/messages?beta=true',
    prefixed: true,
  });

  assert.deepEqual(classifyRequestUrl('/claude-cli/v1/messages'), {
    client: 'claude_cli',
    tool: 'claude',
    strippedUrl: '/v1/messages',
    prefixed: true,
  });

  assert.deepEqual(classifyRequestUrl('/codex-app/v1/responses'), {
    client: 'codex_app',
    tool: 'codex',
    strippedUrl: '/v1/responses',
    prefixed: true,
  });

  assert.deepEqual(classifyRequestUrl('/codex-cli/v1/responses?x=1'), {
    client: 'codex_cli',
    tool: 'codex',
    strippedUrl: '/v1/responses?x=1',
    prefixed: true,
  });
});

test('keeps legacy paths compatible and marks them as unknown clients', () => {
  assert.deepEqual(classifyRequestUrl('/v1/messages?beta=true'), {
    client: 'claude_unknown',
    tool: 'claude',
    strippedUrl: '/v1/messages?beta=true',
    prefixed: false,
  });

  assert.deepEqual(classifyRequestUrl('/v1/responses'), {
    client: 'codex_unknown',
    tool: 'codex',
    strippedUrl: '/v1/responses',
    prefixed: false,
  });
});

test('normalizes Anthropic and OpenAI style usage objects', () => {
  assert.deepEqual(normalizeUsage({ input_tokens: 11, output_tokens: 7 }), {
    input_tokens: 11,
    output_tokens: 7,
    total_tokens: 18,
  });

  assert.deepEqual(normalizeUsage({ prompt_tokens: 5, completion_tokens: 3, total_tokens: 9 }), {
    input_tokens: 5,
    output_tokens: 3,
    total_tokens: 9,
  });

  assert.deepEqual(normalizeUsage(null), {
    input_tokens: 0,
    output_tokens: 0,
    total_tokens: 0,
  });
});

test('aggregates events by tool, client, and upstream model', () => {
  const summary = aggregateEvents([
    {
      tool: 'claude',
      client: 'claude_desktop',
      upstream_model: 'kimi-k2.6',
      status: 200,
      latency_ms: 100,
      usage: { input_tokens: 10, output_tokens: 5, total_tokens: 15 },
    },
    {
      tool: 'claude',
      client: 'claude_desktop',
      upstream_model: 'kimi-k2.6',
      status: 502,
      latency_ms: 300,
      usage: { input_tokens: 0, output_tokens: 0, total_tokens: 0 },
    },
    {
      tool: 'codex',
      client: 'codex_cli',
      upstream_model: 'doubao-seed-2.0-pro',
      status: 200,
      latency_ms: 50,
      usage: { input_tokens: 4, output_tokens: 6, total_tokens: 10 },
    },
  ]);

  assert.equal(summary.total.requests, 3);
  assert.equal(summary.total.failures, 1);
  assert.equal(summary.total.input_tokens, 14);
  assert.equal(summary.total.output_tokens, 11);
  assert.equal(summary.by_client.claude_desktop.requests, 2);
  assert.equal(summary.by_model['kimi-k2.6'].failures, 1);
  assert.equal(summary.by_tool.codex.total_tokens, 10);
});
