import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Wordmark(size: 64)
            Text("A lifting log cast from the gym itself.")
                .font(.title3)
                .foregroundStyle(Palette.slateText)
            Knurl().frame(height: 10).padding(.vertical, 8)
            Spacer()

            SignInWithAppleButton(.signIn) { request in
                auth.prepare(request)
            } onCompletion: { result in
                Task { await auth.complete(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if let message = auth.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Palette.orangeShadow)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bone)
    }
}
