import AuthenticationServices
import CryptoKit
import Foundation
import Supabase

/// Owns the Supabase session. Sign in with Apple → Supabase id-token exchange.
@MainActor
@Observable
final class AuthModel {
    enum State { case loading, signedOut, signedIn }

    private(set) var state: State = .loading
    var errorMessage: String?
    private var currentNonce: String?

    func start() async {
        for await (_, session) in supabase.auth.authStateChanges {
            state = (session?.isExpired == false) ? .signedIn : .signedOut
        }
    }

    /// Configures the Apple request with a hashed nonce.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName]
        request.nonce = Self.sha256(nonce)
    }

    func complete(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                errorMessage = "Apple didn't return an identity token."
                return
            }
            do {
                try await supabase.auth.signInWithIdToken(
                    credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func signOut() async {
        try? await supabase.auth.signOut()
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
