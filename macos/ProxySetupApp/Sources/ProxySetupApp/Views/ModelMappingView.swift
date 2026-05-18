import SwiftUI

struct ModelMappingView: View {
    @Binding var config: SetupConfiguration
    private let reasoningOptions = ["minimal", "low", "medium", "high", "xhigh"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SetupPanel(
                    title: "Claude 模型映射 / Claude Model Mapping",
                    subtitle: "Claude 客户端仍看到标准 Opus、Sonnet、Haiku，代理再映射到上游模型。",
                    systemImage: "arrow.triangle.branch"
                ) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        modelRow("Opus", text: $config.claudeModels.opus)
                        modelRow("Sonnet", text: $config.claudeModels.sonnet)
                        modelRow("Haiku", text: $config.claudeModels.haiku)
                    }
                }

                SetupPanel(
                    title: "Codex Profiles / Codex 配置档",
                    subtitle: "第一个 profile 是 Codex 默认模型；其他 profile 会写入 config.toml，便于 CLI 手工切换。",
                    systemImage: "person.crop.square.stack"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let defaultProfile = config.codexProfiles.first {
                            FeedbackBanner(
                                title: "当前 Codex 默认模型 / Current Codex default",
                                detail: "\(defaultProfile.model) · reasoning \(defaultProfile.reasoningEffort)。Codex 默认只使用这个模型；其他 profile 用于手工切换。",
                                systemImage: "scope",
                                tint: .blue
                            )
                        }

                        ForEach(config.codexProfiles.indices, id: \.self) { index in
                            let profile = config.codexProfiles[index]
                            let profileBinding = $config.codexProfiles[index]
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(profile.name.isEmpty ? "未命名 Profile" : profile.name)
                                        .font(.title3.weight(.semibold))
                                    if index == 0 {
                                        InfoBadge(
                                            text: "默认 / Default",
                                            systemImage: "checkmark.seal.fill",
                                            tint: .green
                                        )
                                    } else {
                                        Button {
                                            makeDefault(profile.id)
                                        } label: {
                                            Label("设为默认 / Make Default", systemImage: "scope")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.regular)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        removeProfile(profile.id)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("删除 profile / Delete profile")
                                    .disabled(config.codexProfiles.count <= 1)
                                }

                                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                                    GridRow {
                                        Text("Profile")
                                            .foregroundStyle(.secondary)
                                        TextField("ark-default", text: profileBinding.name)
                                            .textFieldStyle(.roundedBorder)
                                            .controlSize(.large)
                                    }
                                    GridRow {
                                        Text("Model")
                                            .foregroundStyle(.secondary)
                                        TextField("model-name", text: profileBinding.model)
                                            .textFieldStyle(.roundedBorder)
                                            .controlSize(.large)
                                    }
                                    GridRow {
                                        Text("Reasoning")
                                            .foregroundStyle(.secondary)
                                        Picker("Reasoning", selection: profileBinding.reasoningEffort) {
                                            ForEach(reasoningOptions, id: \.self) { option in
                                                Text(option).tag(option)
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.segmented)
                                        .controlSize(.large)
                                    }
                                }
                                .font(.body)
                            }
                            .padding(16)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        Button {
                            addProfile()
                        } label: {
                            Label("添加 Profile / Add Profile", systemImage: "plus")
                        }
                        .controlSize(.large)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func modelRow(_ label: String, text: Binding<String>) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            TextField("\(label) upstream model", text: text)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
        }
        .font(.body)
    }

    private func addProfile() {
        config.codexProfiles.append(
            CodexProfile(
                id: UUID(),
                name: "custom-\(config.codexProfiles.count + 1)",
                model: "",
                reasoningEffort: "medium"
            )
        )
    }

    private func removeProfile(_ id: UUID) {
        guard config.codexProfiles.count > 1 else { return }
        config.codexProfiles.removeAll { $0.id == id }
    }

    private func makeDefault(_ id: UUID) {
        guard let index = config.codexProfiles.firstIndex(where: { $0.id == id }),
              index != 0 else {
            return
        }
        let profile = config.codexProfiles.remove(at: index)
        config.codexProfiles.insert(profile, at: 0)
    }
}
