import SwiftUI

struct InstallStartControlsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                StatusCallout(
                    text: appState.installationStatusMessage,
                    systemImage: installationStatusIcon,
                    tint: installationStatusTint
                )

                Button {
                    Task {
                        await appState.runInstallation()
                    }
                } label: {
                    Label(
                        appState.isInstalling ? "正在安装 / Installing" : "执行安装 / Install & Start",
                        systemImage: appState.isInstalling ? "hourglass" : "play.fill"
                    )
                    .frame(minWidth: 210)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!appState.canRunInstallation)

                Button {
                    Task {
                        await appState.recheckInstallation()
                    }
                } label: {
                    Label(
                        appState.isVerifyingInstallation ? "验证中 / Rechecking" : "重新验证 / Recheck",
                        systemImage: appState.isVerifyingInstallation ? "hourglass" : "arrow.clockwise"
                    )
                    .frame(minWidth: 170)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(appState.isInstalling || appState.isVerifyingInstallation)
            }

            Label(
                appState.installationDisabledReason,
                systemImage: appState.canRunInstallation ? "checkmark.circle.fill" : "info.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(appState.canRunInstallation ? .green : .orange)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Toggle(
                        "已查看差异预览 / Dry-run reviewed",
                        isOn: $appState.installationConfirmation.reviewedDryRun
                    )
                    .toggleStyle(.checkbox)

                    Toggle(
                        "允许创建备份 / Backups allowed",
                        isOn: $appState.installationConfirmation.createdBackups
                    )
                    .toggleStyle(.checkbox)

                    Toggle(
                        "理解系统变更 / System changes understood",
                        isOn: $appState.installationConfirmation.understandsSystemChanges
                    )
                    .toggleStyle(.checkbox)
                }
                GridRow {
                    Text("确认词 / Confirm")
                        .foregroundStyle(.secondary)
                    TextField("输入大写 INSTALL / Type INSTALL", text: $appState.installationConfirmation.typedPhrase)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .frame(minWidth: 260)
                    Text("按钮会在配置检查通过并输入 INSTALL 后启用。")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout.weight(.semibold))

            if let backupManifestPath = appState.backupManifestPath {
                Label("备份 manifest / Backup manifest: \(backupManifestPath)", systemImage: "archivebox.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            ProgressEventsView(events: appState.installationProgressEvents)
            CommandRecordsView(records: appState.installationCommandRecords)
        }
    }

    private var installationStatusIcon: String {
        if appState.isInstalling || appState.isVerifyingInstallation { return "hourglass" }
        if appState.installationStatusMessage.contains("完成") ||
            appState.installationStatusMessage.contains("验证通过") {
            return "checkmark.seal.fill"
        }
        if appState.installationStatusMessage.contains("失败") ||
            appState.installationStatusMessage.contains("未通过") {
            return "xmark.octagon.fill"
        }
        return "info.circle.fill"
    }

    private var installationStatusTint: Color {
        if appState.isInstalling || appState.isVerifyingInstallation { return .blue }
        if appState.installationStatusMessage.contains("完成") ||
            appState.installationStatusMessage.contains("验证通过") {
            return .green
        }
        if appState.installationStatusMessage.contains("失败") ||
            appState.installationStatusMessage.contains("未通过") {
            return .red
        }
        return .orange
    }
}

struct FactoryRestoreControlsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                StatusCallout(
                    text: appState.factoryRestoreStatusMessage,
                    systemImage: restoreStatusIcon,
                    tint: restoreStatusTint
                )

                Button {
                    Task {
                        await appState.restoreFactoryDefaults()
                    }
                } label: {
                    Label(
                        appState.isRestoringFactoryDefaults
                            ? "正在还原 / Restoring"
                            : "还原原厂服务 / Restore Official Defaults",
                        systemImage: appState.isRestoringFactoryDefaults ? "hourglass" : "arrow.uturn.backward.circle.fill"
                    )
                    .frame(minWidth: 250)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.orange)
                .disabled(!appState.canRestoreFactoryDefaults)
            }

            Label(
                appState.factoryRestoreDisabledReason,
                systemImage: appState.canRestoreFactoryDefaults ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .font(.headline)
            .foregroundStyle(appState.canRestoreFactoryDefaults ? .green : .orange)

            Text("该操作会停止并移除本机代理 LaunchAgent，删除 Claude Desktop 网关配置，移除 Claude CLI 与 Codex 中由本 App 写入的代理片段；Keychain 中的真实 API Key 会保留。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Toggle(
                        "确认先创建备份 / Backup first",
                        isOn: $appState.factoryRestoreConfirmation.reviewedBackups
                    )
                    .toggleStyle(.checkbox)

                    Toggle(
                        "理解将回到官方服务 / Official defaults understood",
                        isOn: $appState.factoryRestoreConfirmation.understandsOfficialDefaults
                    )
                    .toggleStyle(.checkbox)
                }
                GridRow {
                    Text("确认词 / Confirm")
                        .foregroundStyle(.secondary)
                    TextField("输入大写 RESTORE / Type RESTORE", text: $appState.factoryRestoreConfirmation.typedPhrase)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .frame(minWidth: 280)
                    Text("按钮会在两个确认框都勾选，并输入 RESTORE 后启用。")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout.weight(.semibold))

            if let manifestPath = appState.factoryRestoreBackupManifestPath {
                Label("还原备份 manifest / Restore backup manifest: \(manifestPath)", systemImage: "archivebox.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            ProgressEventsView(events: appState.factoryRestoreProgressEvents)
            CommandRecordsView(records: appState.factoryRestoreCommandRecords)
        }
    }

    private var restoreStatusIcon: String {
        if appState.isRestoringFactoryDefaults { return "hourglass" }
        if appState.factoryRestoreStatusMessage.contains("已还原") {
            return "checkmark.seal.fill"
        }
        if appState.factoryRestoreStatusMessage.contains("失败") {
            return "xmark.octagon.fill"
        }
        return "arrow.uturn.backward.circle"
    }

    private var restoreStatusTint: Color {
        if appState.isRestoringFactoryDefaults { return .blue }
        if appState.factoryRestoreStatusMessage.contains("已还原") { return .green }
        if appState.factoryRestoreStatusMessage.contains("失败") { return .red }
        return .orange
    }
}

struct StatusCallout: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.headline.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(tint.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ProgressEventsView: View {
    let events: [InstallationProgressEvent]

    var body: some View {
        if !events.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("当前进度 / Live Progress")
                    .font(.headline)
                ForEach(events) { event in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(for: event.status))
                            .foregroundStyle(tint(for: event.status))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(event.title)
                                    .font(.callout.weight(.semibold))
                                if let elapsed = event.elapsedSeconds {
                                    Text("\(elapsed, specifier: "%.1f")s")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(event.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .textSelection(.enabled)
                            if !event.command.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    Text(event.command.joined(separator: " "))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(tint(for: event.status).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func icon(for status: InstallationProgressStatus) -> String {
        switch status {
        case .running: return "hourglass"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .skipped: return "minus.circle.fill"
        }
    }

    private func tint(for status: InstallationProgressStatus) -> Color {
        switch status {
        case .running: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .skipped: return .secondary
        }
    }
}

struct CommandRecordsView: View {
    let records: [InstallationCommandRecord]

    var body: some View {
        if !records.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("执行记录 / Command Log")
                    .font(.headline)
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(
                            record.title,
                            systemImage: record.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill"
                        )
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(record.succeeded ? .green : .red)
                        Text(record.command.joined(separator: " "))
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                        if !record.stderr.isEmpty {
                            Text(record.stderr)
                                .font(.callout)
                                .foregroundStyle(.red)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }
}
