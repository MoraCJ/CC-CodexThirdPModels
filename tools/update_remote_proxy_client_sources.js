#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const home = process.env.HOME;
const projectRoot = process.cwd();
const ts = new Date().toISOString().replace(/[-:TZ.]/g, '').slice(0, 14);

function backup(file) {
  if (fs.existsSync(file)) {
    fs.copyFileSync(file, `${file}.bak.client-sources.${ts}`);
  }
}

function writeJson(file, data) {
  const mode = fs.statSync(file).mode;
  fs.writeFileSync(file, `${JSON.stringify(data, null, 2)}\n`, { mode });
}

function updateClaudeDesktopConfig() {
  const file = path.join(
    home,
    'Library/Application Support/Claude-3p/configLibrary/120c0c5f-4469-4c91-8ba9-5cadc4e8afee.json'
  );
  backup(file);
  const data = JSON.parse(fs.readFileSync(file, 'utf8'));
  data.inferenceGatewayBaseUrl = 'https://127.0.0.1:38443/claude-desktop';
  writeJson(file, data);
}

function updateClaudeCliConfig() {
  const file = path.join(home, '.claude/settings.json');
  backup(file);
  const data = JSON.parse(fs.readFileSync(file, 'utf8'));
  data.env = data.env || {};
  data.env.ANTHROPIC_BASE_URL = 'https://127.0.0.1:38443/claude-cli';
  writeJson(file, data);
}

function updateCodexConfig() {
  const file = path.join(home, '.codex/config.toml');
  backup(file);
  const mode = fs.statSync(file).mode;
  let toml = fs.readFileSync(file, 'utf8');

  toml = toml.replace(/^model_provider = "ark-coding"$/m, 'model_provider = "ark-coding-app"');
  toml = toml.replace(
    /\[model_providers\.ark-coding\][\s\S]*?\n(?=\[profiles\.)/,
    `[model_providers.ark-coding-app]
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

`
  );
  toml = toml.replace(/^model_provider = "ark-coding"$/gm, 'model_provider = "ark-coding-cli"');
  fs.writeFileSync(file, toml, { mode });
}

function updateClaudeDesktopLauncher() {
  const sourceFile = path.join(projectRoot, 'claude-local-proxy/bin/claude-ca-launcher.c');
  const binaryFile = path.join(projectRoot, 'claude-local-proxy/bin/claude-ca-launcher');
  if (!fs.existsSync(sourceFile)) return false;

  backup(sourceFile);
  backup(binaryFile);
  let source = fs.readFileSync(sourceFile, 'utf8');
  const desktopBaseUrl = 'setenv("ANTHROPIC_BASE_URL", "https://127.0.0.1:38443/claude-desktop", 1);';
  if (source.includes('ANTHROPIC_BASE_URL')) {
    source = source.replace(/setenv\("ANTHROPIC_BASE_URL",\s*"[^"]+",\s*1\);/, desktopBaseUrl);
  } else {
    source = source.replace('  setenv("SSL_CERT_FILE", ca, 0);\n', `  setenv("SSL_CERT_FILE", ca, 0);\n  ${desktopBaseUrl}\n`);
  }
  fs.writeFileSync(sourceFile, source);

  const result = spawnSync('cc', [sourceFile, '-o', binaryFile], { encoding: 'utf8' });
  if (result.status !== 0) {
    throw new Error(`failed to compile launcher: ${result.stderr || result.stdout}`);
  }
  fs.chmodSync(binaryFile, 0o755);
  return true;
}

updateClaudeDesktopConfig();
updateClaudeCliConfig();
updateCodexConfig();
const launcherUpdated = updateClaudeDesktopLauncher();

console.log(
  JSON.stringify(
    {
      ok: true,
      backup_timestamp: ts,
      launcher_updated: launcherUpdated,
      claude_desktop_base_url: 'https://127.0.0.1:38443/claude-desktop',
      claude_cli_base_url: 'https://127.0.0.1:38443/claude-cli',
      codex_app_base_url: 'https://127.0.0.1:38443/codex-app/v1',
      codex_cli_base_url: 'https://127.0.0.1:38443/codex-cli/v1',
    },
    null,
    2
  )
);
