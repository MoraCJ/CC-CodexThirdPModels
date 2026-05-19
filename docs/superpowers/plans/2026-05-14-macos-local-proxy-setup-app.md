# macOS 本机代理设置 App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个本机 macOS SwiftUI App，让用户输入第三方 provider Base URL、API Key 和模型名后，一键安装、配置、启动并验证 Claude Code 与 Codex 的统一本机 HTTPS 代理。

**Architecture:** SwiftUI App 负责编排安装、配置、Keychain、LaunchAgent、证书、验证和状态展示；现有 Node.js 代理继续负责 HTTPS 代理、模型映射、Codex bridge 和 telemetry。真实 provider API Key 存在 macOS Keychain，Node 代理启动或请求时从 Keychain 读取，Claude/Codex 客户端配置只写本地非敏感 token。

**Tech Stack:** SwiftUI、Swift Package Manager、Swift Testing、Foundation、Security.framework、LaunchAgent plist、Node.js、macOS `security` CLI、OpenSSL、现有 `claude-local-proxy`。

**Implementation Note:** 当前开发机器只安装了 CommandLineTools，没有完整 Xcode，也没有 XCTest。所有 Swift 测试统一使用 Swift Testing（`import Testing`、`@Test`、`#expect`），不要再新增 XCTest 依赖。涉及配置写入的任务必须使用临时目录、fixture 或测试专用 Keychain service/account，不能修改本机真实 `~/.codex/config.toml`、`~/.claude/settings.json`、Claude Desktop config、LaunchAgent 或生产 Keychain 项。

---

## 文件结构

新增 macOS App 目录：

```text
macos/ProxySetupApp/
  Package.swift
  Sources/ProxySetupApp/
    ProxySetupApp.swift
    AppState.swift
    Models/SetupConfiguration.swift
    Models/StatusModels.swift
    Services/CommandRunner.swift
    Services/KeychainService.swift
    Services/PreflightService.swift
    Services/ProxyInstaller.swift
    Services/CertificateService.swift
    Services/ClientConfigService.swift
    Services/LaunchAgentService.swift
    Services/VerificationService.swift
    Services/LogService.swift
    Views/RootView.swift
    Views/StatusDashboardView.swift
    Views/SetupWizardView.swift
    Views/ProviderSettingsView.swift
    Views/ModelMappingView.swift
    Views/VerificationResultsView.swift
    Resources/ProxyBundle/server.js
    Resources/ProxyBundle/telemetry.js
    Resources/ProxyBundle/openssl-server.cnf
    Resources/ProxyBundle/bin/claude-ca-launcher.c
  Tests/ProxySetupAppTests/
    SetupConfigurationTests.swift
    KeychainServiceTests.swift
    PreflightServiceTests.swift
    ClientConfigServiceTests.swift
    LaunchAgentServiceTests.swift
    ProxyInstallerTests.swift
    VerificationServiceTests.swift
```

修改现有代理文件：

```text
claude-local-proxy/server.js
claude-local-proxy/keychain.js
claude-local-proxy/tests/keychain.test.js
claude-local-proxy/tests/telemetry.test.js
```

文档更新：

```text
handoff.md
AGENTS.md
docs/superpowers/specs/2026-05-14-macos-local-proxy-setup-app-design.md
```

## 任务卡

### Task 1: Node 代理读取 Keychain 上游 key

**Files:**
- Create: `claude-local-proxy/keychain.js`
- Create: `claude-local-proxy/tests/keychain.test.js`
- Modify: `claude-local-proxy/server.js`
- Test: `claude-local-proxy/tests/keychain.test.js`

- [ ] **Step 1: 写 failing test**

Create `claude-local-proxy/tests/keychain.test.js`:

```js
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
```

- [ ] **Step 2: 运行 test 确认失败**

Run:

```bash
node --test claude-local-proxy/tests/keychain.test.js
```

Expected: FAIL with `Cannot find module '../keychain'`.

- [ ] **Step 3: 实现 `keychain.js`**

Create `claude-local-proxy/keychain.js`:

```js
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
  const value = await reader.read(service, account);
  const key = value || fallback || '';
  return key ? `Bearer ${key}` : '';
}

module.exports = {
  createKeychainReader,
  providerAuthHeader,
};
```

- [ ] **Step 4: 修改 `server.js` 使用真实 provider key**

Modify `claude-local-proxy/server.js`:

```js
const { createKeychainReader, providerAuthHeader } = require('./keychain');

const keychainReader = createKeychainReader();
const keychainService = process.env.KEYCHAIN_SERVICE || 'CJLocalProxy';
const claudeKeychainAccount = process.env.CLAUDE_KEYCHAIN_ACCOUNT || 'claude-upstream-api-key';
const codexKeychainAccount = process.env.CODEX_KEYCHAIN_ACCOUNT || 'codex-upstream-api-key';

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
```

Update Claude passthrough request handling so `scrubHeaders(req.headers)` is followed by:

```js
headers.authorization = await upstreamAuthorization('claude');
```

Update Codex bridge so `callCodexChatCompletions` receives:

```js
const authorization = await upstreamAuthorization('codex');
const chat = await callCodexChatCompletions(chatRequest, authorization);
```

- [ ] **Step 5: 运行 Node tests 和语法检查**

Run:

```bash
node --test claude-local-proxy/tests/keychain.test.js
node --test claude-local-proxy/tests/telemetry.test.js
node --check claude-local-proxy/server.js
node --check claude-local-proxy/telemetry.js
node --check claude-local-proxy/keychain.js
./script/build_and_run.sh --verify
codesign --force --deep --sign - dist/ProxySetupApp.app
codesign --verify --deep --strict --verbose=2 dist/ProxySetupApp.app
ditto -c -k --keepParent dist/ProxySetupApp.app dist/ProxySetupApp-T19-ClaudeDesktop3P-20260519.zip
ditto -x -k dist/ProxySetupApp-T19-ClaudeDesktop3P-20260519.zip /tmp/proxysetupapp-t19-package-check
codesign --verify --deep --strict --verbose=2 /tmp/proxysetupapp-t19-package-check/ProxySetupApp.app
```

交付包：

- `dist/ProxySetupApp-T19-ClaudeDesktop3P-20260519.zip`
- SHA256：`df286017d7928f12e938c5a56a5a090368226bf293d126aef005e3ec57254242`

Expected: all tests pass and checks print no syntax errors.

- [ ] **Step 6: Commit**

```bash
git add claude-local-proxy/server.js claude-local-proxy/keychain.js claude-local-proxy/tests/keychain.test.js
git commit -m "feat: read proxy provider keys from keychain"
```

### Task 2: 创建 SwiftUI App scaffold

**Files:**
- Create: `macos/ProxySetupApp/Package.swift`
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/ProxySetupApp.swift`
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/AppState.swift`
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Views/RootView.swift`
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Views/StatusDashboardView.swift`
- Create: `macos/ProxySetupApp/Tests/ProxySetupAppTests/SmokeTests.swift`

- [ ] **Step 1: 创建 Swift package**

Create `macos/ProxySetupApp/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProxySetupApp",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ProxySetupApp", targets: ["ProxySetupApp"])
    ],
    targets: [
        .executableTarget(
            name: "ProxySetupApp",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ProxySetupAppTests",
            dependencies: ["ProxySetupApp"]
        )
    ]
)
```

Create `macos/ProxySetupApp/Sources/ProxySetupApp/ProxySetupApp.swift`:

```swift
import SwiftUI

@main
struct ProxySetupApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
        MenuBarExtra("Local Proxy", systemImage: appState.menuBarSystemImage) {
            Button("打开设置 / Open Settings") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("打开 Dashboard / Open Dashboard") {
                appState.openDashboard()
            }
            Divider()
            Text(appState.proxyStatusLabel)
        }
    }
}
```

Create `macos/ProxySetupApp/Sources/ProxySetupApp/AppState.swift`:

```swift
import Foundation
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var proxyStatusLabel: String = "未检测 / Not Checked"

    var menuBarSystemImage: String {
        proxyStatusLabel.contains("运行") ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle"
    }

    func openDashboard() {
        guard let url = URL(string: "https://127.0.0.1:38443/dashboard") else { return }
        NSWorkspace.shared.open(url)
    }
}
```

Create `macos/ProxySetupApp/Sources/ProxySetupApp/Views/RootView.swift`:

```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        StatusDashboardView()
            .frame(minWidth: 920, minHeight: 620)
    }
}
```

Create `macos/ProxySetupApp/Sources/ProxySetupApp/Views/StatusDashboardView.swift`:

```swift
import SwiftUI

struct StatusDashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            List {
                Label("状态 / Status", systemImage: "gauge.with.dots.needle.67percent")
                Label("设置向导 / Setup", systemImage: "wand.and.stars")
                Label("日志 / Logs", systemImage: "doc.text.magnifyingglass")
            }
            .navigationSplitViewColumnWidth(220)
        } detail: {
            VStack(alignment: .leading, spacing: 18) {
                Text("Claude + Codex Local Proxy / 本机代理")
                    .font(.title2.bold())
                Text(appState.proxyStatusLabel)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Button("打开 Dashboard / Open Dashboard") {
                    appState.openDashboard()
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
```

Create `macos/ProxySetupApp/Tests/ProxySetupAppTests/SmokeTests.swift`:

```swift
import XCTest
@testable import ProxySetupApp

final class SmokeTests: XCTestCase {
    @MainActor
    func testAppStateHasInitialStatus() {
        let state = AppState()
        XCTAssertEqual(state.proxyStatusLabel, "未检测 / Not Checked")
    }
}
```

- [ ] **Step 2: Build 和 test**

Run:

```bash
cd macos/ProxySetupApp
swift build
swift test
```

Expected: build succeeds and `SmokeTests` passes.

- [ ] **Step 3: Commit**

```bash
git add macos/ProxySetupApp
git commit -m "feat: scaffold macos proxy setup app"
```

### Task 3: 配置模型与校验

**Files:**
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Models/SetupConfiguration.swift`
- Create: `macos/ProxySetupApp/Tests/ProxySetupAppTests/SetupConfigurationTests.swift`

- [ ] **Step 1: 写配置校验 tests**

Create `macos/ProxySetupApp/Tests/ProxySetupAppTests/SetupConfigurationTests.swift`:

```swift
import XCTest
@testable import ProxySetupApp

final class SetupConfigurationTests: XCTestCase {
    func testDefaultConfigurationUsesStableClientPrefixes() throws {
        let config = SetupConfiguration.default
        XCTAssertEqual(config.claudeDesktopBaseURL.absoluteString, "https://127.0.0.1:38443/claude-desktop")
        XCTAssertEqual(config.claudeCLIBaseURL.absoluteString, "https://127.0.0.1:38443/claude-cli")
        XCTAssertEqual(config.codexAppBaseURL.absoluteString, "https://127.0.0.1:38443/codex-app/v1")
        XCTAssertEqual(config.codexCLIBaseURL.absoluteString, "https://127.0.0.1:38443/codex-cli/v1")
    }

    func testRejectsNonHTTPSProviderURL() {
        var config = SetupConfiguration.default
        config.claudeProvider.baseURL = "http://example.com"
        XCTAssertThrowsError(try config.validate())
    }

    func testRequiresAtLeastOneEnabledProvider() {
        var config = SetupConfiguration.default
        config.claudeProvider.isEnabled = false
        config.codexProvider.isEnabled = false
        XCTAssertThrowsError(try config.validate())
    }
}
```

- [ ] **Step 2: 运行 test 确认失败**

Run:

```bash
cd macos/ProxySetupApp
swift test --filter SetupConfigurationTests
```

Expected: FAIL because `SetupConfiguration` is missing.

- [ ] **Step 3: 实现配置模型**

Create `macos/ProxySetupApp/Sources/ProxySetupApp/Models/SetupConfiguration.swift`:

```swift
import Foundation

struct ProviderConfiguration: Equatable, Codable {
    var isEnabled: Bool
    var baseURL: String
    var keychainAccount: String
}

struct ClaudeModelMapping: Equatable, Codable {
    var opus: String
    var sonnet: String
    var haiku: String
}

struct CodexProfile: Identifiable, Equatable, Codable {
    var id: UUID
    var name: String
    var model: String
    var reasoningEffort: String
}

struct SetupConfiguration: Equatable, Codable {
    var listenHost: String
    var listenPort: Int
    var keychainService: String
    var claudeProvider: ProviderConfiguration
    var codexProvider: ProviderConfiguration
    var claudeModels: ClaudeModelMapping
    var codexProfiles: [CodexProfile]

    static let `default` = SetupConfiguration(
        listenHost: "127.0.0.1",
        listenPort: 38443,
        keychainService: "CJLocalProxy",
        claudeProvider: ProviderConfiguration(
            isEnabled: true,
            baseURL: "https://ark.cn-beijing.volces.com/api/coding",
            keychainAccount: "claude-upstream-api-key"
        ),
        codexProvider: ProviderConfiguration(
            isEnabled: true,
            baseURL: "https://ark.cn-beijing.volces.com/api/coding/v3",
            keychainAccount: "codex-upstream-api-key"
        ),
        claudeModels: ClaudeModelMapping(
            opus: "glm-5.1",
            sonnet: "kimi-k2.6",
            haiku: "doubao-seed-2.0-pro"
        ),
        codexProfiles: [
            CodexProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "ark-doubao", model: "doubao-seed-2.0-pro", reasoningEffort: "medium"),
            CodexProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "ark-kimi", model: "kimi-k2.6", reasoningEffort: "high"),
            CodexProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "ark-glm", model: "glm-5.1", reasoningEffort: "high")
        ]
    )

    var claudeDesktopBaseURL: URL { URL(string: "https://\(listenHost):\(listenPort)/claude-desktop")! }
    var claudeCLIBaseURL: URL { URL(string: "https://\(listenHost):\(listenPort)/claude-cli")! }
    var codexAppBaseURL: URL { URL(string: "https://\(listenHost):\(listenPort)/codex-app/v1")! }
    var codexCLIBaseURL: URL { URL(string: "https://\(listenHost):\(listenPort)/codex-cli/v1")! }

    func validate() throws {
        guard claudeProvider.isEnabled || codexProvider.isEnabled else {
            throw ValidationError.noEnabledProvider
        }
        if claudeProvider.isEnabled {
            try validateHTTPS(claudeProvider.baseURL)
        }
        if codexProvider.isEnabled {
            try validateHTTPS(codexProvider.baseURL)
        }
        guard (1...65535).contains(listenPort) else {
            throw ValidationError.invalidPort
        }
    }

    private func validateHTTPS(_ value: String) throws {
        guard let url = URL(string: value), url.scheme == "https", url.host?.isEmpty == false else {
            throw ValidationError.invalidProviderURL(value)
        }
    }

    enum ValidationError: Error, Equatable {
        case noEnabledProvider
        case invalidProviderURL(String)
        case invalidPort
    }
}
```

- [ ] **Step 4: 运行 test**

Run:

```bash
cd macos/ProxySetupApp
swift test --filter SetupConfigurationTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macos/ProxySetupApp/Sources/ProxySetupApp/Models/SetupConfiguration.swift macos/ProxySetupApp/Tests/ProxySetupAppTests/SetupConfigurationTests.swift
git commit -m "feat: add setup configuration model"
```

### Task 4: KeychainService 与脱敏工具

**Files:**
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Services/KeychainService.swift`
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Services/LogService.swift`
- Create: `macos/ProxySetupApp/Tests/ProxySetupAppTests/KeychainServiceTests.swift`

- [ ] **Step 1: 写 Keychain 与脱敏 tests**

Create `macos/ProxySetupApp/Tests/ProxySetupAppTests/KeychainServiceTests.swift`:

```swift
import XCTest
@testable import ProxySetupApp

final class KeychainServiceTests: XCTestCase {
    func testMasksSecrets() {
        XCTAssertEqual(LogService.redact("Authorization: Bearer abcdefghijklmnopqrstuvwxyz"), "Authorization: Bearer <REDACTED>")
        XCTAssertEqual(LogService.maskKey("sk-1234567890abcdef"), "sk-1…cdef")
    }

    func testKeychainRoundTripUsesDedicatedService() throws {
        let service = KeychainService(serviceName: "CJLocalProxyTests")
        let account = "unit-test-\(UUID().uuidString)"
        try service.save("secret-value", account: account)
        XCTAssertEqual(try service.read(account: account), "secret-value")
        try service.delete(account: account)
        XCTAssertNil(try service.read(account: account))
    }
}
```

- [ ] **Step 2: 实现 `LogService`**

Create `macos/ProxySetupApp/Sources/ProxySetupApp/Services/LogService.swift`:

```swift
import Foundation

enum LogService {
    static func redact(_ input: String) -> String {
        input.replacingOccurrences(
            of: #"(?i)(Authorization:\s*Bearer\s+)[A-Za-z0-9._\-]+"#,
            with: "$1<REDACTED>",
            options: .regularExpression
        )
    }

    static func maskKey(_ key: String) -> String {
        guard key.count > 8 else { return "<REDACTED>" }
        return "\(key.prefix(4))…\(key.suffix(4))"
    }
}
```

- [ ] **Step 3: 实现 `KeychainService`**

Create `macos/ProxySetupApp/Sources/ProxySetupApp/Services/KeychainService.swift`:

```swift
import Foundation
import Security

struct KeychainService {
    let serviceName: String

    func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        try delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    func read(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    enum KeychainError: Error, Equatable {
        case unhandled(OSStatus)
    }
}
```

- [ ] **Step 4: 运行 test**

Run:

```bash
cd macos/ProxySetupApp
swift test --filter KeychainServiceTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macos/ProxySetupApp/Sources/ProxySetupApp/Services/KeychainService.swift macos/ProxySetupApp/Sources/ProxySetupApp/Services/LogService.swift macos/ProxySetupApp/Tests/ProxySetupAppTests/KeychainServiceTests.swift
git commit -m "feat: add keychain storage and redaction"
```

### Task 5: 命令执行与环境检查

**Files:**
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Services/CommandRunner.swift`
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Services/PreflightService.swift`
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Models/StatusModels.swift`
- Create: `macos/ProxySetupApp/Tests/ProxySetupAppTests/PreflightServiceTests.swift`

- [ ] **Step 1: 写 Preflight tests**

Create `macos/ProxySetupApp/Tests/ProxySetupAppTests/PreflightServiceTests.swift`:

```swift
import XCTest
@testable import ProxySetupApp

final class PreflightServiceTests: XCTestCase {
    func testParsesCommandAvailability() async throws {
        let runner = MockCommandRunner(outputs: [
            "command -v node": CommandResult(exitCode: 0, stdout: "/opt/homebrew/bin/node\n", stderr: ""),
            "command -v claude": CommandResult(exitCode: 1, stdout: "", stderr: ""),
            "command -v codex": CommandResult(exitCode: 0, stdout: "/opt/homebrew/bin/codex\n", stderr: "")
        ])
        let service = PreflightService(runner: runner)
        let result = await service.checkTools()
        XCTAssertEqual(result.node.path, "/opt/homebrew/bin/node")
        XCTAssertEqual(result.claude.status, .missing)
        XCTAssertEqual(result.codex.path, "/opt/homebrew/bin/codex")
    }
}
```

- [ ] **Step 2: 实现模型与 runner**

Create `macos/ProxySetupApp/Sources/ProxySetupApp/Models/StatusModels.swift`:

```swift
import Foundation

enum CheckStatus: Equatable {
    case ok
    case warning
    case missing
    case failed
}

struct ToolCheck: Equatable {
    var name: String
    var path: String
    var status: CheckStatus
}

struct ToolCheckResult: Equatable {
    var node: ToolCheck
    var claude: ToolCheck
    var codex: ToolCheck
}
```

Create `macos/ProxySetupApp/Sources/ProxySetupApp/Services/CommandRunner.swift`:

```swift
import Foundation

struct CommandResult: Equatable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

protocol CommandRunning {
    func run(_ executable: String, _ arguments: [String]) async -> CommandResult
}

struct CommandRunner: CommandRunning {
    func run(_ executable: String, _ arguments: [String]) async -> CommandResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
            let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return CommandResult(exitCode: process.terminationStatus, stdout: out, stderr: err)
        } catch {
            return CommandResult(exitCode: 127, stdout: "", stderr: String(describing: error))
        }
    }
}

struct MockCommandRunner: CommandRunning {
    var outputs: [String: CommandResult]

    func run(_ executable: String, _ arguments: [String]) async -> CommandResult {
        let key = ([executable] + arguments).joined(separator: " ")
        return outputs[key] ?? CommandResult(exitCode: 127, stdout: "", stderr: "missing mock for \(key)")
    }
}
```

- [ ] **Step 3: 实现 PreflightService**

Create `macos/ProxySetupApp/Sources/ProxySetupApp/Services/PreflightService.swift`:

```swift
import Foundation

struct PreflightService {
    var runner: CommandRunning

    func checkTools() async -> ToolCheckResult {
        async let node = commandCheck("node")
        async let claude = commandCheck("claude")
        async let codex = commandCheck("codex")
        return await ToolCheckResult(node: node, claude: claude, codex: codex)
    }

    private func commandCheck(_ name: String) async -> ToolCheck {
        let result = await runner.run("command", ["-v", name])
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.exitCode == 0, !path.isEmpty {
            return ToolCheck(name: name, path: path, status: .ok)
        }
        return ToolCheck(name: name, path: "", status: .missing)
    }
}
```

- [ ] **Step 4: 运行 test**

Run:

```bash
cd macos/ProxySetupApp
swift test --filter PreflightServiceTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macos/ProxySetupApp/Sources/ProxySetupApp/Services/CommandRunner.swift macos/ProxySetupApp/Sources/ProxySetupApp/Services/PreflightService.swift macos/ProxySetupApp/Sources/ProxySetupApp/Models/StatusModels.swift macos/ProxySetupApp/Tests/ProxySetupAppTests/PreflightServiceTests.swift
git commit -m "feat: add preflight environment checks"
```

### Task 6: 代理文件安装器

**Files:**
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Services/ProxyInstaller.swift`
- Create: `macos/ProxySetupApp/Tests/ProxySetupAppTests/ProxyInstallerTests.swift`
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Resources/ProxyBundle/`

- [ ] **Step 1: 复制代理资源**

Run:

```bash
mkdir -p macos/ProxySetupApp/Sources/ProxySetupApp/Resources/ProxyBundle/bin
cp claude-local-proxy/server.js macos/ProxySetupApp/Sources/ProxySetupApp/Resources/ProxyBundle/server.js
cp claude-local-proxy/telemetry.js macos/ProxySetupApp/Sources/ProxySetupApp/Resources/ProxyBundle/telemetry.js
cp claude-local-proxy/openssl-server.cnf macos/ProxySetupApp/Sources/ProxySetupApp/Resources/ProxyBundle/openssl-server.cnf
cp claude-local-proxy/bin/claude-ca-launcher.c macos/ProxySetupApp/Sources/ProxySetupApp/Resources/ProxyBundle/bin/claude-ca-launcher.c
```

Expected: files exist under `Resources/ProxyBundle`.

- [ ] **Step 2: 写 installer tests**

Create `macos/ProxySetupApp/Tests/ProxySetupAppTests/ProxyInstallerTests.swift`:

```swift
import XCTest
@testable import ProxySetupApp

final class ProxyInstallerTests: XCTestCase {
    func testInstallCreatesExpectedDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let installer = ProxyInstaller(installRoot: root)
        try installer.createDirectories()

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("claude-local-proxy").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("claude-local-proxy/logs").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("claude-local-proxy/certs").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("config").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("backups").path))
    }
}
```

- [ ] **Step 3: 实现 ProxyInstaller**

Create `macos/ProxySetupApp/Sources/ProxySetupApp/Services/ProxyInstaller.swift`:

```swift
import Foundation

struct ProxyInstaller {
    var installRoot: URL

    var proxyDirectory: URL {
        installRoot.appendingPathComponent("claude-local-proxy", isDirectory: true)
    }

    func createDirectories() throws {
        let directories = [
            proxyDirectory,
            proxyDirectory.appendingPathComponent("logs", isDirectory: true),
            proxyDirectory.appendingPathComponent("certs", isDirectory: true),
            installRoot.appendingPathComponent("config", isDirectory: true),
            installRoot.appendingPathComponent("backups", isDirectory: true)
        ]
        for directory in directories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func writeRuntimeConfig(_ config: SetupConfiguration) throws {
        let runtime = [
            "LISTEN_HOST=\(config.listenHost)",
            "LISTEN_PORT=\(config.listenPort)",
            "UPSTREAM_BASE_URL=\(config.claudeProvider.baseURL)",
            "CODEX_UPSTREAM_BASE_URL=\(config.codexProvider.baseURL)",
            "BIG_MODEL=\(config.claudeModels.opus)",
            "MIDDLE_MODEL=\(config.claudeModels.sonnet)",
            "SMALL_MODEL=\(config.claudeModels.haiku)",
            "KEYCHAIN_SERVICE=\(config.keychainService)",
            "CLAUDE_KEYCHAIN_ACCOUNT=\(config.claudeProvider.keychainAccount)",
            "CODEX_KEYCHAIN_ACCOUNT=\(config.codexProvider.keychainAccount)",
            "TELEMETRY_FILE=\(proxyDirectory.path)/logs/telemetry.jsonl"
        ].joined(separator: "\n")

        let configURL = installRoot.appendingPathComponent("config/proxy.env")
        try runtime.write(to: configURL, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 4: 运行 test**

Run:

```bash
cd macos/ProxySetupApp
swift test --filter ProxyInstallerTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macos/ProxySetupApp/Sources/ProxySetupApp/Services/ProxyInstaller.swift macos/ProxySetupApp/Sources/ProxySetupApp/Resources/ProxyBundle macos/ProxySetupApp/Tests/ProxySetupAppTests/ProxyInstallerTests.swift
git commit -m "feat: add proxy installer"
```

### Task 7: 客户端配置生成

**Files:**
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Services/ClientConfigService.swift`
- Create: `macos/ProxySetupApp/Tests/ProxySetupAppTests/ClientConfigServiceTests.swift`

- [ ] **Step 1: 写 config generation tests**

Create `macos/ProxySetupApp/Tests/ProxySetupAppTests/ClientConfigServiceTests.swift`:

```swift
import XCTest
@testable import ProxySetupApp

final class ClientConfigServiceTests: XCTestCase {
    func testClaudeSettingsUsesCliPrefixAndLocalToken() throws {
        let service = ClientConfigService()
        let json = try service.renderClaudeSettings(config: .default)
        XCTAssertTrue(json.contains("https://127.0.0.1:38443/claude-cli"))
        XCTAssertTrue(json.contains("CJ_LOCAL_PROXY_TOKEN"))
        XCTAssertFalse(json.contains("doubao-real-secret"))
    }

    func testCodexConfigSeparatesAppAndCliProviders() {
        let service = ClientConfigService()
        let toml = service.renderCodexConfig(config: .default)
        XCTAssertTrue(toml.contains("[model_providers.ark-coding-app]"))
        XCTAssertTrue(toml.contains("base_url = \"https://127.0.0.1:38443/codex-app/v1\""))
        XCTAssertTrue(toml.contains("[model_providers.ark-coding-cli]"))
        XCTAssertTrue(toml.contains("base_url = \"https://127.0.0.1:38443/codex-cli/v1\""))
    }
}
```

- [ ] **Step 2: 实现 ClientConfigService**

Create `macos/ProxySetupApp/Sources/ProxySetupApp/Services/ClientConfigService.swift`:

```swift
import Foundation

struct ClientConfigService {
    let localToken = "CJ_LOCAL_PROXY_TOKEN"

    func renderClaudeSettings(config: SetupConfiguration) throws -> String {
        let object: [String: Any] = [
            "env": [
                "ANTHROPIC_BASE_URL": config.claudeCLIBaseURL.absoluteString,
                "ANTHROPIC_AUTH_TOKEN": localToken,
                "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-4-6",
                "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-4-6",
                "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4-5",
                "NODE_USE_SYSTEM_CA": "1"
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func renderCodexConfig(config: SetupConfiguration) -> String {
        let profiles = config.codexProfiles.map { profile in
            """
            [profiles.\(profile.name)]
            model_provider = "ark-coding-cli"
            model = "\(profile.model)"
            model_reasoning_effort = "\(profile.reasoningEffort)"
            """
        }.joined(separator: "\n\n")

        return """
        model_provider = "ark-coding-app"
        model = "\(config.codexProfiles.first?.model ?? "doubao-seed-2.0-pro")"
        model_reasoning_effort = "\(config.codexProfiles.first?.reasoningEffort ?? "medium")"
        disable_response_storage = true

        [model_providers.ark-coding-app]
        name = "Third-party provider via CJ Local Proxy - Codex App"
        wire_api = "responses"
        requires_openai_auth = true
        base_url = "\(config.codexAppBaseURL.absoluteString)"
        supports_websockets = false

        [model_providers.ark-coding-cli]
        name = "Third-party provider via CJ Local Proxy - Codex CLI"
        wire_api = "responses"
        requires_openai_auth = true
        base_url = "\(config.codexCLIBaseURL.absoluteString)"
        supports_websockets = false

        \(profiles)
        """
    }
}
```

- [ ] **Step 3: 运行 test**

Run:

```bash
cd macos/ProxySetupApp
swift test --filter ClientConfigServiceTests
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add macos/ProxySetupApp/Sources/ProxySetupApp/Services/ClientConfigService.swift macos/ProxySetupApp/Tests/ProxySetupAppTests/ClientConfigServiceTests.swift
git commit -m "feat: generate claude and codex configs"
```

### Task 8: LaunchAgent plist 生成与控制

**Files:**
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Services/LaunchAgentService.swift`
- Create: `macos/ProxySetupApp/Tests/ProxySetupAppTests/LaunchAgentServiceTests.swift`

- [ ] **Step 1: 写 plist tests**

Create `macos/ProxySetupApp/Tests/ProxySetupAppTests/LaunchAgentServiceTests.swift`:

```swift
import XCTest
@testable import ProxySetupApp

final class LaunchAgentServiceTests: XCTestCase {
    func testPlistContainsRunAtLoadKeepAliveAndNoSecret() throws {
        let service = LaunchAgentService(label: "com.cj.claude-local-https-proxy")
        let plist = service.renderPlist(
            nodePath: "/opt/homebrew/bin/node",
            proxyDirectory: URL(fileURLWithPath: "/tmp/CJLocalProxy/claude-local-proxy"),
            config: .default
        )

        XCTAssertTrue(plist.contains("<key>RunAtLoad</key>"))
        XCTAssertTrue(plist.contains("<key>KeepAlive</key>"))
        XCTAssertTrue(plist.contains("KEYCHAIN_SERVICE"))
        XCTAssertFalse(plist.contains("sk-"))
        XCTAssertFalse(plist.contains("Bearer "))
    }
}
```

- [ ] **Step 2: 实现 LaunchAgentService**

Create `macos/ProxySetupApp/Sources/ProxySetupApp/Services/LaunchAgentService.swift`:

```swift
import Foundation

struct LaunchAgentService {
    var label: String

    func renderPlist(nodePath: String, proxyDirectory: URL, config: SetupConfiguration) -> String {
        let proxyPath = proxyDirectory.path
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(label)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(nodePath)</string>
            <string>\(proxyPath)/server.js</string>
          </array>
          <key>WorkingDirectory</key>
          <string>\(proxyPath)</string>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>StandardOutPath</key>
          <string>\(proxyPath)/logs/proxy.log</string>
          <key>StandardErrorPath</key>
          <string>\(proxyPath)/logs/proxy.err.log</string>
          <key>EnvironmentVariables</key>
          <dict>
            <key>LISTEN_HOST</key><string>\(config.listenHost)</string>
            <key>LISTEN_PORT</key><string>\(config.listenPort)</string>
            <key>UPSTREAM_BASE_URL</key><string>\(config.claudeProvider.baseURL)</string>
            <key>CODEX_UPSTREAM_BASE_URL</key><string>\(config.codexProvider.baseURL)</string>
            <key>BIG_MODEL</key><string>\(config.claudeModels.opus)</string>
            <key>MIDDLE_MODEL</key><string>\(config.claudeModels.sonnet)</string>
            <key>SMALL_MODEL</key><string>\(config.claudeModels.haiku)</string>
            <key>KEYCHAIN_SERVICE</key><string>\(config.keychainService)</string>
            <key>CLAUDE_KEYCHAIN_ACCOUNT</key><string>\(config.claudeProvider.keychainAccount)</string>
            <key>CODEX_KEYCHAIN_ACCOUNT</key><string>\(config.codexProvider.keychainAccount)</string>
            <key>TLS_CERT_FILE</key><string>\(proxyPath)/certs/server.crt</string>
            <key>TLS_KEY_FILE</key><string>\(proxyPath)/certs/server.key</string>
            <key>TELEMETRY_FILE</key><string>\(proxyPath)/logs/telemetry.jsonl</string>
          </dict>
        </dict>
        </plist>
        """
    }
}
```

- [ ] **Step 3: 运行 test**

Run:

```bash
cd macos/ProxySetupApp
swift test --filter LaunchAgentServiceTests
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add macos/ProxySetupApp/Sources/ProxySetupApp/Services/LaunchAgentService.swift macos/ProxySetupApp/Tests/ProxySetupAppTests/LaunchAgentServiceTests.swift
git commit -m "feat: generate launchagent plist"
```

### Task 9: 证书服务

**Files:**
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Services/CertificateService.swift`
- Test: `macos/ProxySetupApp/Tests/ProxySetupAppTests/CertificateServiceTests.swift`

- [ ] **Step 1: 写证书命令 tests**

Create `macos/ProxySetupApp/Tests/ProxySetupAppTests/CertificateServiceTests.swift`:

```swift
import XCTest
@testable import ProxySetupApp

final class CertificateServiceTests: XCTestCase {
    func testOpenSSLConfigContainsLocalSANs() {
        let config = CertificateService.renderOpenSSLConfig()
        XCTAssertTrue(config.contains("IP.1 = 127.0.0.1"))
        XCTAssertTrue(config.contains("DNS.1 = localhost"))
        XCTAssertTrue(config.contains("IP.2 = ::1"))
    }
}
```

- [ ] **Step 2: 实现 CertificateService**

Create `macos/ProxySetupApp/Sources/ProxySetupApp/Services/CertificateService.swift`:

```swift
import Foundation

struct CertificateService {
    static func renderOpenSSLConfig() -> String {
        """
        [req]
        default_bits = 2048
        prompt = no
        default_md = sha256
        req_extensions = req_ext
        distinguished_name = dn

        [dn]
        CN = localhost

        [req_ext]
        subjectAltName = @alt_names

        [alt_names]
        IP.1 = 127.0.0.1
        IP.2 = ::1
        DNS.1 = localhost
        """
    }

    func generationCommands(certsDirectory: URL) -> [[String]] {
        let dir = certsDirectory.path
        return [
            ["openssl", "genrsa", "-out", "\(dir)/ca.key", "2048"],
            ["openssl", "req", "-x509", "-new", "-nodes", "-key", "\(dir)/ca.key", "-sha256", "-days", "3650", "-out", "\(dir)/ca.crt", "-subj", "/CN=CJ Local Proxy CA"],
            ["openssl", "genrsa", "-out", "\(dir)/server.key", "2048"],
            ["openssl", "req", "-new", "-key", "\(dir)/server.key", "-out", "\(dir)/server.csr", "-config", "\(dir)/openssl-server.cnf"],
            ["openssl", "x509", "-req", "-in", "\(dir)/server.csr", "-CA", "\(dir)/ca.crt", "-CAkey", "\(dir)/ca.key", "-CAcreateserial", "-out", "\(dir)/server.crt", "-days", "825", "-sha256", "-extensions", "req_ext", "-extfile", "\(dir)/openssl-server.cnf"]
        ]
    }
}
```

- [ ] **Step 3: 运行 test**

Run:

```bash
cd macos/ProxySetupApp
swift test --filter CertificateServiceTests
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add macos/ProxySetupApp/Sources/ProxySetupApp/Services/CertificateService.swift macos/ProxySetupApp/Tests/ProxySetupAppTests/CertificateServiceTests.swift
git commit -m "feat: add certificate generation service"
```

### Task 10: 验证与状态汇总

**Files:**
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Services/VerificationService.swift`
- Create: `macos/ProxySetupApp/Tests/ProxySetupAppTests/VerificationServiceTests.swift`

- [ ] **Step 1: 写 Verification tests**

Create `macos/ProxySetupApp/Tests/ProxySetupAppTests/VerificationServiceTests.swift`:

```swift
import XCTest
@testable import ProxySetupApp

final class VerificationServiceTests: XCTestCase {
    func testBuildsExpectedHealthURLs() {
        let urls = VerificationService.healthURLs(config: .default).map(\.absoluteString)
        XCTAssertEqual(urls, [
            "https://127.0.0.1:38443/health",
            "https://127.0.0.1:38443/dashboard",
            "https://127.0.0.1:38443/telemetry/summary",
            "https://127.0.0.1:38443/claude-desktop/health",
            "https://127.0.0.1:38443/claude-cli/health",
            "https://127.0.0.1:38443/codex-app/health",
            "https://127.0.0.1:38443/codex-cli/health"
        ])
    }
}
```

- [ ] **Step 2: 实现 VerificationService**

Create `macos/ProxySetupApp/Sources/ProxySetupApp/Services/VerificationService.swift`:

```swift
import Foundation

struct VerificationService {
    static func healthURLs(config: SetupConfiguration) -> [URL] {
        let base = "https://\(config.listenHost):\(config.listenPort)"
        return [
            "\(base)/health",
            "\(base)/dashboard",
            "\(base)/telemetry/summary",
            "\(base)/claude-desktop/health",
            "\(base)/claude-cli/health",
            "\(base)/codex-app/health",
            "\(base)/codex-cli/health"
        ].compactMap(URL.init(string:))
    }
}
```

- [ ] **Step 3: 运行 test**

Run:

```bash
cd macos/ProxySetupApp
swift test --filter VerificationServiceTests
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add macos/ProxySetupApp/Sources/ProxySetupApp/Services/VerificationService.swift macos/ProxySetupApp/Tests/ProxySetupAppTests/VerificationServiceTests.swift
git commit -m "feat: add verification service"
```

### Task 11: 设置向导 UI

**Files:**
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Views/SetupWizardView.swift`
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Views/ProviderSettingsView.swift`
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Views/ModelMappingView.swift`
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Views/VerificationResultsView.swift`
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/Views/RootView.swift`
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/AppState.swift`

- [ ] **Step 1: 扩展 AppState**

Modify `macos/ProxySetupApp/Sources/ProxySetupApp/AppState.swift`:

```swift
@MainActor
final class AppState: ObservableObject {
    @Published var proxyStatusLabel: String = "未检测 / Not Checked"
    @Published var setupConfiguration: SetupConfiguration = .default
    @Published var selectedSection: Section = .status

    enum Section: String, CaseIterable, Identifiable {
        case status
        case setup
        case logs

        var id: String { rawValue }
        var title: String {
            switch self {
            case .status: return "状态 / Status"
            case .setup: return "设置向导 / Setup"
            case .logs: return "日志 / Logs"
            }
        }
    }

    var menuBarSystemImage: String {
        proxyStatusLabel.contains("运行") ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle"
    }

    func openDashboard() {
        guard let url = URL(string: "https://127.0.0.1:38443/dashboard") else { return }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 2: 创建设置视图**

Create `macos/ProxySetupApp/Sources/ProxySetupApp/Views/ProviderSettingsView.swift`:

```swift
import SwiftUI

struct ProviderSettingsView: View {
    @Binding var config: SetupConfiguration

    var body: some View {
        Form {
            Toggle("启用 Claude / Enable Claude", isOn: $config.claudeProvider.isEnabled)
            TextField("Claude Base URL", text: $config.claudeProvider.baseURL)
            Toggle("启用 Codex / Enable Codex", isOn: $config.codexProvider.isEnabled)
            TextField("Codex Base URL", text: $config.codexProvider.baseURL)
        }
    }
}
```

Create `macos/ProxySetupApp/Sources/ProxySetupApp/Views/ModelMappingView.swift`:

```swift
import SwiftUI

struct ModelMappingView: View {
    @Binding var config: SetupConfiguration

    var body: some View {
        Form {
            Section("Claude 模型映射 / Claude Model Mapping") {
                TextField("Opus 上游模型", text: $config.claudeModels.opus)
                TextField("Sonnet 上游模型", text: $config.claudeModels.sonnet)
                TextField("Haiku 上游模型", text: $config.claudeModels.haiku)
            }
            Section("Codex Profiles") {
                ForEach($config.codexProfiles) { $profile in
                    HStack {
                        TextField("Profile", text: $profile.name)
                        TextField("Model", text: $profile.model)
                        TextField("Reasoning", text: $profile.reasoningEffort)
                    }
                }
            }
        }
    }
}
```

Create `macos/ProxySetupApp/Sources/ProxySetupApp/Views/VerificationResultsView.swift`:

```swift
import SwiftUI

struct VerificationResultsView: View {
    let config: SetupConfiguration

    var body: some View {
        List(VerificationService.healthURLs(config: config), id: \.absoluteString) { url in
            Label(url.absoluteString, systemImage: "checkmark.circle")
        }
    }
}
```

Create `macos/ProxySetupApp/Sources/ProxySetupApp/Views/SetupWizardView.swift`:

```swift
import SwiftUI

struct SetupWizardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            ProviderSettingsView(config: $appState.setupConfiguration)
                .tabItem { Text("Provider") }
            ModelMappingView(config: $appState.setupConfiguration)
                .tabItem { Text("Models") }
            VerificationResultsView(config: appState.setupConfiguration)
                .tabItem { Text("Verify") }
        }
        .padding(24)
    }
}
```

- [ ] **Step 3: 接入 RootView**

Modify `macos/ProxySetupApp/Sources/ProxySetupApp/Views/RootView.swift`:

```swift
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            List(AppState.Section.allCases, selection: $appState.selectedSection) { section in
                Text(section.title)
            }
            .navigationSplitViewColumnWidth(220)
        } detail: {
            switch appState.selectedSection {
            case .status:
                StatusDashboardView()
            case .setup:
                SetupWizardView()
            case .logs:
                Text("日志 / Logs")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 920, minHeight: 620)
    }
}
```

- [ ] **Step 4: Build**

Run:

```bash
cd macos/ProxySetupApp
swift build
swift test
```

Expected: build succeeds and all tests pass.

- [ ] **Step 5: Commit**

```bash
git add macos/ProxySetupApp/Sources/ProxySetupApp
git commit -m "feat: add setup wizard UI"
```

### Task 12: 集成验证、文档和 handoff

**Files:**
- Modify: `handoff.md`
- Modify: `AGENTS.md`
- Modify: `docs/superpowers/specs/2026-05-14-macos-local-proxy-setup-app-design.md`
- Create: `macos/ProxySetupApp/README.md`

- [ ] **Step 1: 写 App README**

Create `macos/ProxySetupApp/README.md`:

```markdown
# macOS 本机代理设置 App

这个 App 用于在本机配置 Claude Code Desktop/CLI 与 Codex App/CLI 的统一 HTTPS 代理。

## 开发运行

```bash
cd macos/ProxySetupApp
swift build
swift test
swift run ProxySetupApp
```

## 安全约束

- 真实 API Key 存入 macOS Keychain。
- Claude/Codex 配置不写真实 API Key。
- LaunchAgent plist 不写真实 API Key。
- App 日志和代理 telemetry 不记录 prompt、response、Authorization、Cookie 或真实 key。
```

- [ ] **Step 2: 更新 handoff**

Append to the top section of `handoff.md`:

```markdown
### macOS App 实现计划

- 任务卡：`docs/superpowers/plans/2026-05-14-macos-local-proxy-setup-app.md`。
- 实现目录：`macos/ProxySetupApp/`。
- 第一阶段先完成 Node 代理 Keychain 读取，再做 SwiftUI App scaffold、配置模型、KeychainService、Preflight、ProxyInstaller、ClientConfig、LaunchAgent、Certificate、Verification 和 UI。
```

- [ ] **Step 3: 运行全量验证**

Run:

```bash
node --test claude-local-proxy/tests/telemetry.test.js
node --test claude-local-proxy/tests/keychain.test.js
node --check claude-local-proxy/server.js
node --check claude-local-proxy/telemetry.js
node --check claude-local-proxy/keychain.js
cd macos/ProxySetupApp && swift test && swift build
```

Expected: all tests and builds pass.

- [ ] **Step 4: Commit**

```bash
git add handoff.md AGENTS.md docs/superpowers/specs/2026-05-14-macos-local-proxy-setup-app-design.md macos/ProxySetupApp/README.md
git commit -m "docs: document macos setup app"
```

### Task 13: 本机安装编排与安全预览

**Files:**
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Services/LocalInstallationService.swift`
- Create: `macos/ProxySetupApp/Tests/ProxySetupAppTests/LocalInstallationServiceTests.swift`
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/Views/VerificationResultsView.swift`
- Modify: `handoff.md`
- Modify: `macos/ProxySetupApp/README.md`
- Modify: `docs/superpowers/specs/2026-05-14-macos-local-proxy-setup-app-design.md`

- [ ] **Step 1: 写安装编排测试**

覆盖：

- `buildPlan` 生成本机安装步骤、LaunchAgent 命令预览、证书信任命令预览、verification summary。
- `buildPlan` 拒绝非法配置。
- `prepareLocalFiles` 只写入注入的临时 `installRoot` 和 `launchAgentDirectory`。
- 生成代理文件、`config/proxy.env`、`certs/openssl-server.cnf` 和 `<label>.plist`。
- 生成内容不包含真实 API Key、`Bearer ` 或 `sk-`。

- [ ] **Step 2: 实现 `LocalInstallationService`**

实现：

- `InstallationEnvironment`：安装目录、LaunchAgent 目录、Node path、user id、login keychain path。
- `InstallationPlanItem`：UI 可展示的安装步骤。
- `LocalInstallationResult`：生成文件路径、launchctl 命令数组、证书信任命令数组和 pending verification summary。
- `buildPlan(config:environment:)`：只生成计划，不写文件。
- `prepareLocalFiles(config:environment:proxySourceDirectory:)`：只写入注入目录，不执行 `launchctl`、`security` 或 `openssl`。

- [ ] **Step 3: 接入 UI 预览**

在 `VerificationResultsView` 显示：

- 安装计划。
- 安全边界说明。
- 配置无效时展示错误，不静默吞掉错误。

- [ ] **Step 4: 更新文档和 handoff**

记录：

- 当前只实现安装编排和安全预览。
- 自动化测试只写临时目录。
- 真实安装执行路径仍需 CJ 明确确认后再接入。

- [ ] **Step 5: 验证**

Run:

```bash
cd macos/ProxySetupApp
swift test --filter LocalInstallationServiceTests
swift test
swift build
cd ../..
node --test claude-local-proxy/tests/telemetry.test.js claude-local-proxy/tests/keychain.test.js
node --check claude-local-proxy/server.js
node --check claude-local-proxy/telemetry.js
node --check claude-local-proxy/keychain.js
./script/build_and_run.sh --verify
```

Expected: all tests/builds pass. App launch verification must not write real Claude/Codex config, LaunchAgent, or production Keychain.

### Task 14: 安装确认、备份、回滚与 dry-run diff

**Files:**
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Services/InstallationSafetyService.swift`
- Create: `macos/ProxySetupApp/Tests/ProxySetupAppTests/InstallationSafetyServiceTests.swift`
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/Services/LocalInstallationService.swift`
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/Services/ClientConfigService.swift`
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/Services/ProxyInstaller.swift`
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/AppState.swift`
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/Views/SetupWizardView.swift`
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/Views/VerificationResultsView.swift`
- Modify: `macos/ProxySetupApp/Tests/ProxySetupAppTests/SmokeTests.swift`
- Modify: `handoff.md`
- Modify: `macos/ProxySetupApp/README.md`
- Modify: `docs/superpowers/specs/2026-05-14-macos-local-proxy-setup-app-design.md`

- [x] **Step 1: 写 safety tests**

覆盖：

- `dryRun` 对 managed files 返回 `create`、`update`、`unchanged`，且不写目标文件。
- dry-run preview 必须脱敏 `Bearer ...` 与 `sk-...` 形态的密钥。
- `createBackups` 只备份已存在文件，记录 manifest，不把 proposed contents 写入 manifest。
- `rollback` 只按 manifest 恢复已存在文件、删除原本不存在但被安装创建的文件。
- 缺 backup 时回滚失败，不静默跳过。
- `rollback` 必须限制在显式传入的 allowed target roots 内。
- `InstallationConfirmation` 必须满足所有确认项并输入 `INSTALL` 才允许继续。
- `KeychainWriteConfirmation` 必须确认账号、确认写入 Keychain 并输入 `KEYCHAIN` 才允许保存 key。

- [x] **Step 2: 实现 `InstallationSafetyService`**

实现：

- `ManagedFileChange`：title、targetURL、proposedContents。
- `DryRunFileDiff`：change、kind、preview。
- `BackupManifest` / `BackupEntry`。
- `InstallationConfirmation` 与确认要求。
- `KeychainWriteConfirmation`。
- `dryRun(changes:)`、`createBackups(for:backupDirectory:timestamp:)`、`rollback(manifest:allowedTargetRoots:)`。

- [x] **Step 3: 让服务生成 managed changes**

实现：

- `ProxyInstaller.renderRuntimeConfig`，供写入和 dry-run 共用。
- `LocalInstallationService.managedFileChanges`：生成 proxy runtime、OpenSSL config、LaunchAgent plist 三类 changes。
- `ClientConfigEnvironment` 与 `ClientConfigService.managedClientConfigChanges`：用注入路径生成 Claude CLI、Claude Desktop gateway、Codex config 三类 changes。

- [x] **Step 4: 接入 UI 预览**

在 `VerificationResultsView` 显示：

- dry-run diff。
- create/update/unchanged 状态。
- execution gate 确认要求。
- 明确当前页面只读，不写入、不备份、不执行系统命令。

在 `SetupWizardView` / `AppState` 中：

- “保存 Key / Save Keys” 需要用户勾选账号核对、确认 Keychain 写入，并输入 `KEYCHAIN`。
- 未满足确认条件时按钮禁用；即使直接调用状态方法也会被 guard 拦截，不写生产 Keychain。

- [x] **Step 5: 更新文档和 handoff**

记录：

- 当前已经有 dry-run、backup manifest、rollback 和 confirmation gate。
- dry-run preview 会做密钥脱敏。
- rollback 需要显式 allowed target roots。
- 保存 provider key 需要 `KEYCHAIN` 确认门禁。
- 自动化测试只使用临时目录。
- 真实安装按钮仍需后续任务接入显式确认、备份和回滚流程。

- [x] **Step 6: 验证**

Run:

```bash
cd macos/ProxySetupApp
swift test --filter InstallationSafetyServiceTests
swift test
swift build
cd ../..
node --test claude-local-proxy/tests/telemetry.test.js claude-local-proxy/tests/keychain.test.js
node --check claude-local-proxy/server.js
node --check claude-local-proxy/telemetry.js
node --check claude-local-proxy/keychain.js
./script/build_and_run.sh --verify
```

Expected: all tests/builds pass. No command should modify real Claude/Codex config, real LaunchAgents, production Keychain, or execute real system install commands.

### Task 15: 真实安装执行、可用性 UI 与 AppIcon

**Files:**
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Services/InstallationExecutionService.swift`
- Create: `macos/ProxySetupApp/Tests/ProxySetupAppTests/InstallationExecutionServiceTests.swift`
- Create: `macos/ProxySetupApp/Assets/AppIconSource.png`
- Create: `macos/ProxySetupApp/Assets/AppIcon.iconset/*`
- Create: `macos/ProxySetupApp/Assets/AppIcon.icns`
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/AppState.swift`
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/Services/ClientConfigService.swift`
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/Services/VerificationService.swift`
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/Views/SetupWizardView.swift`
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/Views/ModelMappingView.swift`
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/Views/VerificationResultsView.swift`
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/Views/SetupUIComponents.swift`
- Modify: `macos/ProxySetupApp/Package.swift`
- Modify: `script/build_and_run.sh`
- Modify: `macos/ProxySetupApp/README.md`
- Modify: `handoff.md`

- [x] **Step 1: 写安装执行 tests**

覆盖：注入临时目录执行安装、`INSTALL` 门禁、backup manifest、代理文件复制、Claude/Codex 客户端配置写入、OpenSSL/security/launchctl/curl 命令记录、失败命令中断、manifest 不含真实 key。

- [x] **Step 2: 实现 `InstallationExecutionService`**

执行顺序：校验配置与确认门禁；创建备份；准备代理文件、runtime config、OpenSSL config、LaunchAgent plist；写 Claude CLI、Claude Desktop 3P、Codex config；生成证书；信任本机 CA；bootstrap/kickstart LaunchAgent；运行 health 验证。

- [x] **Step 3: 接入 AppState 与验证页真实安装按钮**

`AppState` 新增安装状态、命令记录、备份 manifest 路径和验证结果；验证页从只读 gate 升级为 `执行安装 / Install & Start`，只有配置检查通过、三个确认项完成并输入 `INSTALL` 后启用。

- [x] **Step 4: 修正 Claude Desktop 与 Codex 默认模型可用性**

Claude Desktop 当时改为写入 `Claude-3p/configLibrary/cj-local-proxy.json`、`_meta.json` 和 `claude_desktop_config.json`；Codex 顶层默认模型明确使用第一个 profile，模型页提供“设为默认 / Make Default”按钮。注意：Claude Desktop 1.7196+ 已在 Task 19 修正为 UUID configLibrary 文件与新字段 schema。

- [x] **Step 5: UI 可用性与 AppIcon**

放大 Setup Step 三段切换控件；Check 按钮与 Save Keys 使用一致的 prominent 样式和状态色；两张提示卡统一最小高度；使用 CJ 提供的“哇！通过啦！”图片生成 `AppIcon.icns`；打包脚本复制 AppIcon 与 SwiftPM resource bundle。

- [x] **Step 6: 验证**

Run:

```bash
cd macos/ProxySetupApp
swift test
swift build
cd ../..
./script/build_and_run.sh --verify
```

Expected: Swift tests/builds pass；`.app` 可启动；`.app` 内包含 `ProxySetupApp_ProxySetupApp.bundle/ProxyBundle/*` 与 `Contents/Resources/AppIcon.icns`；自动化验证只启动 App，不点击真实安装，不写本机真实配置。

### Task 16: 安装后验证重试与手动重新验证

**Files:**
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/Services/VerificationService.swift`
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/AppState.swift`
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/Views/VerificationResultsView.swift`
- Modify: `macos/ProxySetupApp/Tests/ProxySetupAppTests/VerificationServiceTests.swift`
- Modify: `macos/ProxySetupApp/Tests/ProxySetupAppTests/SmokeTests.swift`
- Modify: `macos/ProxySetupApp/README.md`
- Modify: `handoff.md`

- [x] **Step 1: 写重试验证 tests**

覆盖：

- 前几次 curl 返回 `HTTP 000` / connection refused，后续返回 200 时，验证应最终通过。
- 重试耗尽后，验证应保留 curl stderr，方便用户判断连接失败原因。
- AppState 可在不重装的情况下触发重新验证，并更新安装状态与 proxy status。

- [x] **Step 2: 实现验证重试**

- `VerificationService.run` 新增 `attempts` 与 `retryDelayNanoseconds`。
- 默认每个端点最多重试 8 次，间隔 0.5 秒。
- curl 参数改为 `-skS --connect-timeout 2 --max-time 5`，既跳过本机自签证书校验，又能显示连接错误。

- [x] **Step 3: 接入 UI**

- 验证端点卡片新增 `重新验证 / Recheck`。
- 执行安装区域新增 `重新验证 / Recheck`。
- Recheck 只运行 health 验证，不重新安装、不重新写配置、不重新生成证书。

- [x] **Step 4: 验证**

Run:

```bash
cd macos/ProxySetupApp
swift test
swift build
cd ../..
node --check claude-local-proxy/server.js
node --check claude-local-proxy/telemetry.js
node --check claude-local-proxy/keychain.js
./script/build_and_run.sh --verify
codesign --verify --deep --strict --verbose=2 dist/ProxySetupApp.app
```

Expected: tests/builds pass；`.app` 可启动；自动化验证不触发真实安装。

### Task 17: 启动配置独立入口与还原原厂服务

**Files:**
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Services/FactoryRestoreService.swift`
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Views/StartupConfigurationView.swift`
- Create: `macos/ProxySetupApp/Sources/ProxySetupApp/Views/StartupActionsView.swift`
- Create: `macos/ProxySetupApp/Tests/ProxySetupAppTests/FactoryRestoreServiceTests.swift`
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/AppState.swift`
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/Views/RootView.swift`
- Modify: `macos/ProxySetupApp/Sources/ProxySetupApp/Views/VerificationResultsView.swift`
- Modify: `macos/ProxySetupApp/Tests/ProxySetupAppTests/SmokeTests.swift`
- Modify: `macos/ProxySetupApp/README.md`
- Modify: `handoff.md`

- [x] **Step 1: 写还原原厂配置 tests**

覆盖：使用临时目录模拟已安装代理配置；还原时只移除本 App 管理的 Claude CLI env、Claude Desktop 3P gateway/meta/deploymentMode、Codex proxy providers/profiles 和 LaunchAgent plist；保留用户其它 Claude/Codex 配置；还原前创建 backup manifest；缺少 `RESTORE` 确认时拒绝执行。

- [x] **Step 2: 实现 `FactoryRestoreService`**

执行顺序：确认门禁；为 6 个目标文件创建备份；执行 `launchctl bootout` 停止 LaunchAgent；删除本 App 的 Claude Desktop gateway；清理 Claude Desktop meta/deploymentMode；清理 Claude CLI 和 Codex 中的代理片段；删除 LaunchAgent plist。Keychain 中真实 API Key 不删除。

- [x] **Step 3: 接入 AppState**

新增 `FactoryRestoreConfirmation`、还原状态、命令记录、备份 manifest 路径、还原按钮启用条件和 `restoreFactoryDefaults()`。还原成功后清空安装验证结果，并把 proxy status 标记为已回到官方服务。

- [x] **Step 4: 接入 UI**

左侧菜单新增 `启动配置 / Start`，App 默认打开此页；页面集中放置 `检查配置 / Check`、`重新验证 / Recheck`、`打开 Dashboard`、`安装并启动 / Install & Start` 与 `还原原厂服务 / Restore Official Defaults`。验证页安装区域改为复用同一套安装控件。

- [x] **Step 5: 验证与打包**

Run:

```bash
cd macos/ProxySetupApp
swift test
swift build
cd ../..
node --check claude-local-proxy/server.js
node --check claude-local-proxy/telemetry.js
node --check claude-local-proxy/keychain.js
./script/build_and_run.sh --verify
codesign --verify --deep --strict --verbose=2 dist/ProxySetupApp.app
```

Expected: tests/builds pass；`.app` 可启动；`.app` 内包含资源 bundle 与 AppIcon；自动化验证只启动 App，不点击真实安装或还原，不写本机真实配置。

## 自检清单

- Spec 覆盖：
  - 本机部署：Task 2-12 覆盖。
  - 用户输入 Base URL、API Key、模型名：Task 3、4、7、11 覆盖。
  - Keychain 安全存储：Task 1、4、8 覆盖。
  - 代理安装：Task 6 覆盖。
  - 证书生成与信任引导基础：Task 9 覆盖。
  - Claude/Codex 四类前缀配置：Task 3、7、10 覆盖。
  - LaunchAgent `RunAtLoad` / `KeepAlive`：Task 8 覆盖。
  - Dashboard 与 telemetry 验证：Task 10 覆盖。
  - 菜单栏与主状态页：Task 2、11 覆盖。
  - 文档与 handoff：Task 12 覆盖。
  - 本机安装编排与安全预览：Task 13 覆盖。
  - dry-run、备份、回滚、确认门禁：Task 14 覆盖。
  - 真实安装执行按钮、安装命令记录、AppIcon 和资源 bundle 打包：Task 15 覆盖。
  - 安装后验证重试与手动 recheck：Task 16 覆盖。
  - 启动配置独立入口与还原原厂服务：Task 17 覆盖。
- 范围边界：
  - 不做远程 SSH。
  - 不做签名 `.pkg`。
  - 不自动安装 Node.js、Claude Code 或 Codex。
  - Task 13 不执行真实 `launchctl`、`security add-trusted-cert` 或 `openssl`。
  - Task 14 不写真实用户配置；只做临时目录测试与 UI 只读预览。
  - Task 15 自动化测试只使用注入临时目录；真实安装必须由用户在 App 内完成检查和 `INSTALL` 门禁后手动触发。
  - Task 16 只重试 health 验证；`Recheck` 不重装、不写配置、不动 Keychain。
  - Task 17 自动化测试只使用临时目录；真实还原必须由用户在 App 内完成备份确认、官方服务确认并输入 `RESTORE` 后手动触发；还原不会删除 Keychain 中的真实 API Key。
  - 不记录 prompt、response、Authorization、Cookie 或真实 API Key。
- 执行顺序：
  - Task 1 必须先执行，因为 App 的安全设计依赖代理能从 Keychain 读取真实上游 key。
  - Task 2-5 建立 App 和核心服务测试基础。
  - Task 6-10 完成安装、配置、LaunchAgent、证书和验证能力。
  - Task 11-12 完成 UI 和文档收口。

## Task 18：测试机问题整改：依赖探测、流式安装、五栏流程

状态：已完成。

整改目标：

- 修复测试机因 LaunchAgent 写死 `/opt/homebrew/bin/node` 导致 `EX_CONFIG` 和安装卡住的问题。
- 安装与还原过程实时输出当前步骤、命令、耗时和结果。
- 左侧导航重构为 `状态`、`设置`、`启动配置`、`还原配置`、`日志` 五栏。

关键实现：

- `PreflightService` 现在探测 `node`、`npm`、`brew`、`claude`、`codex` 的真实路径；`node` 为必需依赖，缺失阻断安装；其它工具缺失只警告。
- `InstallationEnvironment.defaultEnvironment()` 不再写死 Node 路径；安装服务在需要时通过 preflight 解析真实 `node` 并写入 LaunchAgent plist。
- `CommandRunner` 增加 timeout，避免外部命令无期限等待。
- `InstallationExecutionService`、`VerificationService`、`FactoryRestoreService` 增加 progress callback，UI 可实时显示安装、验证和还原状态。
- 状态页内置读取 `/telemetry/summary` 的 token 用量摘要，仍保留打开 dashboard 的入口。
- 日志页展示本次安装/还原记录，并只读 tail `proxy.log`、`proxy.err.log`、`telemetry.jsonl`。

验证：

```bash
cd macos/ProxySetupApp && swift build
cd macos/ProxySetupApp && swift test
node --check claude-local-proxy/server.js
node --check claude-local-proxy/telemetry.js
node --check claude-local-proxy/keychain.js
./script/build_and_run.sh --verify
codesign --force --deep --sign - dist/ProxySetupApp.app
codesign --verify --deep --strict --verbose=2 dist/ProxySetupApp.app
ditto -c -k --keepParent dist/ProxySetupApp.app dist/ProxySetupApp-T18-FlowStreaming-20260519.zip
ditto -x -k dist/ProxySetupApp-T18-FlowStreaming-20260519.zip /tmp/proxysetupapp-t18-package-check
codesign --verify --deep --strict --verbose=2 /tmp/proxysetupapp-t18-package-check/ProxySetupApp.app
```

交付包：

- `dist/ProxySetupApp-T18-FlowStreaming-20260519.zip`
- SHA256：`5f6ed4922b46810eeaf66eab5e9a6a41ba99457a7607da5df41dedccb3a7f1fd`

## Task 19：Claude Desktop 1.7196+ 3P configLibrary 兼容修复

状态：已完成。

远端测试机现象：

- 代理和 LaunchAgent 正常，`/health`、`/claude-cli/health`、`/claude-desktop/health` 均返回 200。
- Claude Code CLI 已能通过 `/claude-cli` 调用代理。
- Claude Desktop 启动后黑屏，进程仍以 `deploymentMode: 1p` 和默认 `~/Library/Application Support/Claude` 用户数据目录运行。
- `~/Library/Logs/Claude-3p/main.log` 不存在，代理日志没有 `/claude-desktop` 请求。

根因：

- 当前 App 写入的 Desktop 配置仍是旧格式：`configLibrary/cj-local-proxy.json`、`_meta.json.configs`、`gatewayBaseUrl/gatewayApiKey`。
- Claude Desktop 1.7196+ 的 3P configLibrary 读取逻辑要求 `_meta.json.appliedId` 是 UUID，并读取 `configLibrary/<UUID>.json`。
- 新版本配置字段要求使用 `inferenceProvider`、`inferenceGatewayBaseUrl`、`inferenceGatewayApiKey`、`inferenceGatewayAuthScheme`、`inferenceModels`。
- 由于 `appliedId` 不是 UUID 且字段不匹配，Claude Desktop 忽略本 App 写入的 3P 配置，继续走官方 1P bootstrap，于是出现 `app-unavailable-in-region` 黑屏。

关键实现：

- `ClientConfigEnvironment` 增加稳定 UUID：`9f5d0b76-5b35-4c9e-9d5d-2f2a8f8f8c01`。
- Claude Desktop gateway 文件改为写入 `Claude-3p/configLibrary/<UUID>.json`。
- gateway 配置改为新 schema：
  - `inferenceProvider: gateway`
  - `inferenceGatewayBaseUrl`
  - `inferenceGatewayApiKey`
  - `inferenceGatewayAuthScheme: bearer`
  - `inferenceModels` 使用 `name` + `labelOverride`
  - `disableDeploymentModeChooser: true`
  - `unstableDisableModelVerification: true`
- `_meta.json` 同时写 `appliedId`、`entries`、`configs`、`isManaged: false`，兼容新旧 UI 读取。
- 还原原厂服务同时清理新版 UUID gateway 和旧版 `cj-local-proxy.json`，并从 `entries/configs/appliedId` 中移除本 App 管理项。

验证：

```bash
cd macos/ProxySetupApp && swift build
cd macos/ProxySetupApp && swift test
node --check claude-local-proxy/server.js
node --check claude-local-proxy/telemetry.js
node --check claude-local-proxy/keychain.js
```
