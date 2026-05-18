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
                    subtitle: "每个 profile 会生成独立模型和 reasoning effort，便于 CLI 选择。",
                    systemImage: "person.crop.square.stack"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach($config.codexProfiles) { $profile in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(profile.name.isEmpty ? "未命名 Profile" : profile.name)
                                        .font(.title3.weight(.semibold))
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
                                        TextField("ark-default", text: $profile.name)
                                            .textFieldStyle(.roundedBorder)
                                            .controlSize(.large)
                                    }
                                    GridRow {
                                        Text("Model")
                                            .foregroundStyle(.secondary)
                                        TextField("model-name", text: $profile.model)
                                            .textFieldStyle(.roundedBorder)
                                            .controlSize(.large)
                                    }
                                    GridRow {
                                        Text("Reasoning")
                                            .foregroundStyle(.secondary)
                                        Picker("Reasoning", selection: $profile.reasoningEffort) {
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
}
