import SwiftUI

struct VerificationResultsView: View {
    let config: SetupConfiguration

    var body: some View {
        List(VerificationService.healthURLs(config: config), id: \.absoluteString) { url in
            Label(url.absoluteString, systemImage: "checkmark.circle")
        }
    }
}
