# CJ Local Proxy macOS App 操作手册

适用版本：`ProxySetupApp-T20-DesktopHostInit-20260519`

本手册用于在一台 macOS 测试机或新电脑上，通过 `CJ Local Proxy` App 配置 Claude Code Desktop/CLI 与 Codex App/CLI 使用本机 HTTPS 代理访问第三方模型服务商，并在需要时一键还原回官方服务。

## 1. 准备工作

### 1.1 需要提前安装的软件

- macOS 14 或更新版本。
- Claude Code Desktop / Claude Code CLI，按实际需要安装。若这台 Mac 无法访问 `downloads.claude.ai`，建议同时安装 Claude Code CLI，因为 App 会用本机 CLI 初始化 Claude Desktop 运行组件。
- Codex App / Codex CLI，按实际需要安装。

配置代理本身不要求先打开 Claude 或 Codex，但建议安装完成后至少打开一次对应客户端，确认系统已经创建基础目录。完成代理安装后，需要重启 Claude/Codex 客户端，让它们重新读取配置。

### 1.2 获取 App

当前测试包：

```text
dist/ProxySetupApp-T20-DesktopHostInit-20260519.zip
```

SHA256：

```text
5c29c339216ee05b6c908bfa869082a61bf5bc70c551fcb02e54e983a4e80187
```

复制到测试机后解压，得到：

```text
ProxySetupApp.app
```

如果 macOS 提示来自未验证开发者，可右键 App 选择 `打开 / Open`，或先执行：

```bash
xattr -dr com.apple.quarantine ProxySetupApp.app
open ProxySetupApp.app
```

## 2. 首次打开界面

App 打开后默认进入左侧菜单的：

```text
状态 / Status
```

常用页面：

- `状态 / Status`：查看代理状态、LaunchAgent、证书、客户端路径和 token 用量摘要。
- `设置 / Settings`：填写 Base URL、API Key、Keychain account、模型映射。
- `启动配置 / Start`：检查依赖、配置本机代理 host/port、安装启动、重新验证。
- `还原配置 / Restore`：把 Claude 与 Codex 还原到官方默认服务。
- `日志 / Logs`：查看安装日志、还原日志和代理运行日志。

## 3. 填写服务商与 Key

进入左侧：

```text
设置 / Settings
```

### 3.1 Provider 页面

Claude Code 区域：

- `启用 / Enable`：需要 Claude 走代理时打开。
- `兼容类型 / Compatibility`：
  - 上游是 Anthropic 兼容接口，选 `Anthropic-compatible`。
  - 上游是 OpenAI 兼容接口，选 `OpenAI-compatible`。
- `Base URL`：填写第三方模型服务商给你的 HTTPS Base URL。
- `API Key`：粘贴 Claude 上游 provider key。保存后 App 会清空明文输入框。
- `Keychain`：通常保留默认 `claude-upstream-api-key`。

Codex 区域：

- `启用 / Enable`：需要 Codex 走代理时打开。
- `兼容类型 / Compatibility`：通常 Codex 使用 OpenAI 兼容接口，选 `OpenAI-compatible`。
- `Base URL`：填写 Codex 上游 provider 的 HTTPS Base URL。
- `API Key`：粘贴 Codex 上游 provider key。保存后 App 会清空明文输入框。
- `Keychain`：通常保留默认 `codex-upstream-api-key`。

本机代理 `Host`、`Port`、`Keychain service` 已移动到左侧：

```text
启动配置 / Start
```

默认值：

- `Host`：默认 `127.0.0.1`。
- `Port`：默认 `38443`。
- `Keychain`：默认 `CJLocalProxy`，表示 macOS Keychain service 名称。

不要随意改 Keychain 名称和 account；除非你明确知道自己要创建另一套隔离配置。

### 3.2 保存 Key

底部保存前需要完成三个动作：

1. 勾选 `已核对账号 / Accounts reviewed`。
2. 勾选 `确认写入 Keychain / Confirm Keychain write`。
3. 在确认输入框输入大写：

```text
KEYCHAIN
```

然后点击：

```text
保存 Key / Save Keys
```

macOS 弹出 Keychain 授权窗口时：

- 输入当前 macOS 登录密码，不是 API Key，也不是服务商账号密码。
- 如果是代理或 dashboard 运行时访问 Keychain，建议点 `始终允许 / Always Allow`，减少后续反复弹窗。
- 如果只是临时确认，也可以点 `允许 / Allow`。

保存成功信号：

- 右侧提示变成 `Keychain 已保存 / Saved`。
- API Key 输入框被清空。
- 底部提示显示已保存的 account 名称。

## 4. 配置模型

进入 `设置 / Settings` 的：

```text
模型 / Models
```

### 4.1 Claude 模型映射

Claude 客户端仍会看到标准 Opus、Sonnet、Haiku 槽位，代理会映射到上游模型：

- `Opus`：填写你希望 Opus 槽位使用的上游模型名。
- `Sonnet`：填写你希望 Sonnet 槽位使用的上游模型名。
- `Haiku`：填写你希望 Haiku 槽位使用的上游模型名。

示例：

```text
Opus   -> glm-5.1
Sonnet -> kimi-k2.6
Haiku  -> doubao-seed-2.0-pro
```

### 4.2 Codex 模型

Codex 当前实际默认使用一个顶层模型。App 中第一个 Codex profile 会写入为默认模型。

操作建议：

- 把最常用的 Codex 模型放在第一个 profile。
- 如果页面提供 `设为默认 / Make Default`，点击后该 profile 会移动为默认。
- 其它 profile 会写入配置，便于后续手工切换。

## 5. 检查配置

回到左侧：

```text
启动配置 / Start
```

点击：

```text
检查配置 / Check
```

通过信号：

- 按钮或状态提示变成绿色。
- 提示类似 `配置与必需依赖可用 / Configuration and required dependencies look valid`。
- `外部依赖 / External Dependencies` 会显示 `node`、`npm`、`brew`、`claude`、`codex` 的真实路径或缺失提示。

未通过时：

- 根据橙色提示修正 Base URL、端口、模型名或 provider 启用状态。
- Base URL 必须是 `https://` 开头。
- `node` 是必需依赖，缺失时不能安装；`npm`、`brew`、`claude`、`codex` 缺失只会警告，不阻断代理安装。

### 5.1 Claude Desktop Host 检查

`启动配置 / Start` 里还有一块：

```text
Claude Desktop Host / Desktop 运行组件
```

这里用于解决一种常见情况：Claude CLI 已经能用，但 Claude Desktop Cowork/Code 没有回复，并提示：

```text
Host Claude Code binary not available. Check that the download completed.
```

这通常表示 Claude Desktop 想从 `downloads.claude.ai` 下载自己的 host bundle，但当前网络下载失败。它不是 `npm` 或 `brew` 目录问题，也不是截图里 Settings/Profile 的名字问题。

操作方式：

1. `Data root` 默认保持 `Claude-3p`。只有确认 Desktop 使用了其它 3P 数据目录时才修改。
2. 点击 `检查 Host / Check Host`。
3. 如果提示未解析到版本，先打开 Claude Desktop 一次，让它写出 `main.log`，再回到 App 重新检查。
4. 如果已经解析到版本但缺少 host binary，点击 `初始化 Host / Initialize Host`。

初始化会做这些事：

- 在 `~/Library/Application Support/<Data root>/claude-code/<version>/` 下创建 Desktop 期望的目录。
- 创建 `.verified`，避免 Desktop 把目录当作未完成下载并清理。
- 创建 `claude.app/Contents/MacOS/claude` 和同级 `claude` 两个入口，指向本机代理目录中的 `claude-ca-launcher`。
- `claude-ca-launcher` 会调用本机 `claude` CLI，并注入本地 CA、`/claude-desktop` Base URL 和本机占位 token。

初始化不会做这些事：

- 不会下载 Claude 官方 host bundle。
- 不会把官方 bundle 放进 App 或仓库。
- 不会写真实 API Key。

初始化完成后，完全退出并重新打开 Claude Desktop，再发起一次简单对话。若仍失败，到 `日志 / Logs` 查看 `Desktop Host 日志 / Desktop Host Log`。

## 6. 安装并启动代理

在 `启动配置 / Start` 页面找到：

```text
安装并启动 / Install & Start
```

安装前需要完成：

1. 勾选 `已查看差异预览 / Dry-run reviewed`。
2. 勾选 `允许创建备份 / Backups allowed`。
3. 勾选 `理解系统变更 / System changes understood`。
4. 输入大写确认词：

```text
INSTALL
```

然后点击：

```text
执行安装 / Install & Start
```

安装会做这些事：

- 创建 backup manifest。
- 复制本机代理文件到 `~/Library/Application Support/CJLocalProxy/`。
- 写入代理运行配置。
- 生成本机 HTTPS 证书。
- 信任本机 CA。
- 写入 LaunchAgent，并配置开机自启与 KeepAlive。
- 写入 Claude/Codex 客户端配置。
- 启动代理并验证 health 端点。

macOS 可能再次要求 Keychain 或证书信任授权，输入当前 Mac 登录密码即可。

安装过程中 App 会实时显示：

- 当前步骤。
- 正在执行的命令。
- 成功、失败、跳过状态。
- 命令耗时。
- 正在验证的 endpoint。

正常安装通常应在几十秒内完成。若某一步失败，不需要猜测卡在哪里，直接查看页面中的 `当前进度 / Live Progress` 或左侧 `日志 / Logs`。

成功信号：

- 状态显示 `安装完成并验证通过 / Installed and verified`。
- `Proxy health`、`Dashboard`、`Telemetry summary` 等端点为绿色。
- Dashboard 可打开。

如果安装完成但验证失败，先等 5-10 秒，然后点：

```text
重新验证 / Recheck
```

首次安装时 `Stop existing LaunchAgent` 失败通常可以忽略，因为旧服务可能本来不存在。

## 7. 验证是否可用

### 7.1 打开 Dashboard

在 `启动配置 / Start` 页面点击：

```text
打开 Dashboard / Open Dashboard
```

或浏览器打开：

```text
https://127.0.0.1:38443/dashboard
```

如果浏览器弹出 Keychain 授权：

- 输入当前 Mac 登录密码。
- 可选择 `始终允许 / Always Allow`。

Dashboard 会按客户端区分用量：

- Claude Desktop：`/claude-desktop`
- Claude CLI：`/claude-cli`
- Codex App：`/codex-app/v1`
- Codex CLI：`/codex-cli/v1`

### 7.2 命令行检查

```bash
curl -sk https://127.0.0.1:38443/health
curl -sk https://127.0.0.1:38443/telemetry/summary
```

LaunchAgent 检查：

```bash
launchctl print gui/$(id -u)/com.cj.claude-local-https-proxy
```

重点看：

```text
state = running
runatload
keepalive
```

### 7.3 重启客户端

安装完成后，建议完全退出并重新打开：

- Claude Code Desktop。
- Claude Code CLI 终端 session。
- Codex App。
- Codex CLI 终端 session。

然后分别发起一次简单请求，回到 Dashboard 看请求数和模型统计是否增长。

## 8. 还原原厂服务

如果你想暂时不用第三方代理，回到 Claude/Codex 官方服务，进入：

```text
还原配置 / Restore
```

找到：

```text
还原原厂服务 / Restore Official Defaults
```

还原前需要完成：

1. 勾选 `确认先创建备份 / Backup first`。
2. 勾选 `理解将回到官方服务 / Official defaults understood`。
3. 输入大写确认词：

```text
RESTORE
```

然后点击：

```text
还原原厂服务 / Restore Official Defaults
```

还原会做这些事：

- 停止本机代理 LaunchAgent。
- 删除本 App 管理的 LaunchAgent plist。
- 删除 Claude Desktop 的本 App gateway 配置；新版使用 UUID 配置文件，同时会清理旧版 `cj-local-proxy` gateway 文件。
- 从 Claude Desktop meta/deployment mode 中移除本 App 写入的 3P 配置。
- 从 Claude CLI settings 中移除本 App 写入的代理 env key。
- 从 Codex config 中移除本 App 写入的 proxy provider、profile 和默认模型片段。
- 保留用户其它 Claude/Codex 配置。
- 保留 Keychain 中保存的真实 API Key。

还原后需要重启 Claude/Codex 客户端。

## 9. 常见问题

### 9.1 `保存 Key / Save Keys` 按钮不可点

检查：

- 是否粘贴了至少一个 API Key。
- 是否勾选了两个确认框。
- 是否输入了大写 `KEYCHAIN`。

`KEYCHAIN` 必须全大写，这是为了避免误触写入真实 Keychain。

### 9.2 点击保存 Key 后失败

优先确认：

- Keychain service 是否为默认 `CJLocalProxy`。
- Keychain account 是否为默认 `claude-upstream-api-key` 或 `codex-upstream-api-key`。
- macOS 是否弹出过钥匙串权限窗口，且输入的是当前 Mac 登录密码。

如果仍失败，退出 App 后重新打开再试。

### 9.3 Dashboard 打开后弹密码框

这是 macOS Keychain 授权，不是网页密码。

输入当前 Mac 登录密码。为了让代理服务后续能自动读取 Keychain，可以点：

```text
始终允许 / Always Allow
```

### 9.4 安装后端点显示 HTTP 000

先等 5-10 秒，然后在 App 中点击：

```text
重新验证 / Recheck
```

如果仍失败，检查：

优先进入 `日志 / Logs` 查看 `proxy.err.log`、`proxy.log` 和安装日志；也可以在终端执行：

```bash
launchctl print gui/$(id -u)/com.cj.claude-local-https-proxy
```

### 9.5 Claude 或 Codex 仍然走官方服务

检查：

- 是否已经执行 `Install & Start`。
- 是否重启了对应客户端。
- Dashboard 中对应客户端路径是否出现请求。
- Claude Desktop、Codex App 如果安装后从未打开过，可先打开一次再重启。

### 9.6 想重新配置不同服务商

流程：

1. 到 `设置 / Settings` 修改 Base URL、Key、模型。
2. 保存新的 Key。
3. 点击 `检查配置 / Check`。
4. 输入 `INSTALL` 后重新执行 `Install & Start`。

重新安装会先生成备份。

## 10. 安全边界

- App 不会自动保存 Key；必须用户输入 `KEYCHAIN` 并点击保存。
- App 不会自动安装；必须用户输入 `INSTALL` 并点击安装。
- App 不会自动还原；必须用户输入 `RESTORE` 并点击还原。
- 代理 telemetry 不记录 prompt、response、Authorization、Cookie 或真实 API Key。
- 还原原厂服务不会删除 Keychain 中的真实 API Key。
