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
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Profile")
                                .foregroundStyle(.secondary)
                            TextField("Profile", text: $profile.name)
                        }
                        GridRow {
                            Text("Model")
                                .foregroundStyle(.secondary)
                            TextField("Model", text: $profile.model)
                        }
                        GridRow {
                            Text("Reasoning")
                                .foregroundStyle(.secondary)
                            TextField("Reasoning", text: $profile.reasoningEffort)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .formStyle(.grouped)
    }
}
