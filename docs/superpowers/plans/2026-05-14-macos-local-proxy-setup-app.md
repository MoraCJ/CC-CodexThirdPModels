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
```

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
- 范围边界：
  - 不做远程 SSH。
  - 不做签名 `.pkg`。
  - 不自动安装 Node.js、Claude Code 或 Codex。
  - 不记录 prompt、response、Authorization、Cookie 或真实 API Key。
- 执行顺序：
  - Task 1 必须先执行，因为 App 的安全设计依赖代理能从 Keychain 读取真实上游 key。
  - Task 2-5 建立 App 和核心服务测试基础。
  - Task 6-10 完成安装、配置、LaunchAgent、证书和验证能力。
  - Task 11-12 完成 UI 和文档收口。
