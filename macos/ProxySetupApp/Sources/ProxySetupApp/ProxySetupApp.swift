import SwiftUI

@main
struct ProxySetupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("CJ Local Proxy", id: "main") {
            RootView()
                .environmentObject(appState)
        }

        MenuBarExtra("Local Proxy", systemImage: appState.menuBarSystemImage) {
            Button("Open Settings") {
                appDelegate.showMainWindow()
            }
            Button("Open Dashboard") {
                appState.openDashboard()
            }
            Divider()
            Text(appState.proxyStatusLabel)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        showMainWindow()
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}
