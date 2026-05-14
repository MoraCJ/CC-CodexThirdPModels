import SwiftUI

struct SetupWizardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("设置向导 / Setup Wizard")
                    .font(.title2.bold())
                Text("当前界面只编辑内存配置；应用到本机前会另行确认。")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            TabView {
                ProviderSettingsView(config: $appState.setupConfiguration)
                    .tabItem { Text("Provider") }

                ModelMappingView(config: $appState.setupConfiguration)
                    .tabItem { Text("Models") }

                VerificationResultsView(config: appState.setupConfiguration)
                    .tabItem { Text("Verify") }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}
