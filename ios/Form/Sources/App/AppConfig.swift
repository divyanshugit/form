import Foundation
import Supabase

enum AppConfig {
    /// Values come from Config/Secrets.xcconfig via Info.plist (never hardcoded in source).
    static let supabaseURL: URL = {
        let host = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_HOST") as? String ?? ""
        guard let url = URL(string: "https://\(host)"), !host.isEmpty else {
            fatalError("SUPABASE_HOST missing — copy Config/Secrets.example.xcconfig to Secrets.xcconfig")
        }
        return url
    }()

    static let supabaseAnonKey: String = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String, !key.isEmpty else {
            fatalError("SUPABASE_ANON_KEY missing — copy Config/Secrets.example.xcconfig to Secrets.xcconfig")
        }
        return key
    }()
}

/// Shared client. All Form tables live in the dedicated `form` schema.
let supabase = SupabaseClient(
    supabaseURL: AppConfig.supabaseURL,
    supabaseKey: AppConfig.supabaseAnonKey,
    options: SupabaseClientOptions(db: .init(schema: "form"))
)
