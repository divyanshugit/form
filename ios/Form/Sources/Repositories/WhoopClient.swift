import Foundation
import Supabase

/// Talks to the `whoop` edge function. The app never sees WHOOP tokens or the client secret.
protocol WhoopClient: Sendable {
    func exchange(code: String, redirectURI: String) async throws
    func disconnect() async throws
    func isConnected() async throws -> Bool
    func recoveries(since: Date) async throws -> [WhoopRecovery]
    func sleeps(since: Date) async throws -> [WhoopSleep]
    func cycles(since: Date) async throws -> [WhoopCycle]
    /// Pages through WHOOP workouts, newest first. `since: nil` walks the whole history.
    func workouts(since: Date?, maxRecords: Int) async throws -> [WhoopWorkout]
}

enum WhoopConfig {
    /// Public OAuth client id (the secret lives only in the edge function).
    static let clientID = "d52bb811-5bc1-4238-a4d8-92f58dcad5ab"
    /// Registered in the WHOOP developer dashboard. ASWebAuthenticationSession captures it directly.
    static let redirectURI = "stacked://whoop/callback"
    static let callbackScheme = "stacked"
    static let scopes = "read:recovery read:sleep read:workout read:cycles read:profile offline"

    static func authorizeURL(state: String) -> URL {
        var components = URLComponents(string: "https://api.prod.whoop.com/oauth/oauth2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }
}

struct SupabaseWhoopClient: WhoopClient {
    private struct Request: Encodable {
        var action: String
        var path: String?
        var params: [String: String]?
        var code: String?
        var redirect_uri: String?
    }

    private struct StatusRow: Decodable { let user_id: UUID }

    private func get<T: Decodable & Sendable>(_ path: String, params: [String: String]) async throws -> WhoopPage<T> {
        try await supabase.functions.invoke(
            "whoop",
            options: FunctionInvokeOptions(body: Request(action: "get", path: path, params: params)),
            decoder: JSONDecoder.whoop
        )
    }

    func exchange(code: String, redirectURI: String) async throws {
        try await supabase.functions.invoke(
            "whoop",
            options: FunctionInvokeOptions(body: Request(action: "exchange", code: code, redirect_uri: redirectURI))
        )
    }

    func disconnect() async throws {
        try await supabase.functions.invoke("whoop", options: FunctionInvokeOptions(body: Request(action: "disconnect")))
    }

    func isConnected() async throws -> Bool {
        let rows: [StatusRow] = try await supabase.from("whoop_status").select("user_id").execute().value
        return !rows.isEmpty
    }

    /// Walks WHOOP's pagination (25 records per page, nextToken) from `since` until done or `maxRecords`.
    private func pages<T: Decodable & Sendable>(_ path: String, since: Date?, maxRecords: Int) async throws -> [T] {
        var all: [T] = []
        var next: String?
        repeat {
            var params = ["limit": "25"] // WHOOP's maximum page size
            if let since { params["start"] = ISO8601DateFormatter().string(from: since) }
            if let next { params["nextToken"] = next }
            let page: WhoopPage<T> = try await get(path, params: params)
            all += page.records
            next = page.nextToken
        } while next != nil && all.count < maxRecords
        return all
    }

    func recoveries(since: Date) async throws -> [WhoopRecovery] {
        try await pages("/v2/recovery", since: since, maxRecords: 400)
    }

    func sleeps(since: Date) async throws -> [WhoopSleep] {
        try await pages("/v2/activity/sleep", since: since, maxRecords: 400)
    }

    func cycles(since: Date) async throws -> [WhoopCycle] {
        try await pages("/v2/cycle", since: since, maxRecords: 400)
    }

    func workouts(since: Date?, maxRecords: Int) async throws -> [WhoopWorkout] {
        try await pages("/v2/activity/workout", since: since, maxRecords: maxRecords)
    }
}
