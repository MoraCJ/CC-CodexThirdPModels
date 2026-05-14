'use strict';

const { spawn } = require('child_process');

function defaultRunSecurity(args) {
  return new Promise((resolve, reject) => {
    const child = spawn('/usr/bin/security', args, {
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';

    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString('utf8');
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString('utf8');
    });
    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0) {
        resolve(stdout);
        return;
      }
      reject(new Error(stderr.trim() || `security exited with ${code}`));
    });
  });
}

function createKeychainReader(options = {}) {
  const runSecurity = options.runSecurity || defaultRunSecurity;
  const cache = new Map();

  return {
    async read(service, account) {
      if (!service || !account) return '';
      const cacheKey = `${service}\u0000${account}`;
      if (cache.has(cacheKey)) return cache.get(cacheKey);

      const output = await runSecurity([
        'find-generic-password',
        '-s',
        service,
        '-a',
        account,
        '-w',
      ]);
      const value = String(output || '').trim();
      cache.set(cacheKey, value);
      return value;
    },
  };
}

async function providerAuthHeader({ reader, service, account, fallback }) {
  let value = '';
  try {
    value = await reader.read(service, account);
  } catch (error) {
    if (!fallback) throw error;
  }
  const key = value || fallback || '';
  return key ? `Bearer ${key}` : '';
}

module.exports = {
  createKeychainReader,
  providerAuthHeader,
};
