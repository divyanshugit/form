import SwiftUI

/// Tabs whose screens land in later phases (PRs, Photos, Journal).
struct ComingSoonView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.bone)
                .navigationTitle(title)
        }
    }
}
