'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {
  createKeychainReader,
  providerAuthHeader,
} = require('../keychain');

test('reads provider key through injected security runner and caches value', async () => {
  const calls = [];
  const reader = createKeychainReader({
    runSecurity: async (args) => {
      calls.push(args);
      assert.deepEqual(args, [
        'find-generic-password',
        '-s',
        'CJLocalProxy',
        '-a',
        'claude-upstream-api-key',
        '-w',
      ]);
      return 'secret-value\n';
    },
  });

  const first = await reader.read('CJLocalProxy', 'claude-upstream-api-key');
  const second = await reader.read('CJLocalProxy', 'claude-upstream-api-key');

  assert.equal(first, 'secret-value');
  assert.equal(second, 'secret-value');
  assert.equal(calls.length, 1);
});

test('returns empty string when service or account is missing', async () => {
  const reader = createKeychainReader({
    runSecurity: async () => {
      throw new Error('security should not run');
    },
  });

  assert.equal(await reader.read('', 'account'), '');
  assert.equal(await reader.read('service', ''), '');
});

test('builds bearer auth header from provider-specific keychain settings', async () => {
  const reader = createKeychainReader({
    runSecurity: async () => 'provider-key',
  });

  const header = await providerAuthHeader({
    reader,
    service: 'CJLocalProxy',
    account: 'codex-upstream-api-key',
  });

  assert.equal(header, 'Bearer provider-key');
});

test('uses fallback when keychain lookup fails', async () => {
  const reader = createKeychainReader({
    runSecurity: async () => {
      throw new Error('item not found');
    },
  });

  const header = await providerAuthHeader({
    reader,
    service: 'CJLocalProxy',
    account: 'missing-account',
    fallback: 'fallback-key',
  });

  assert.equal(header, 'Bearer fallback-key');
});
