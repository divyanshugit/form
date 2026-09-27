import XCTest
@testable import Form

/// Simulates the edge function in front of WHOOP: the access token has expired, and WHOOP's
/// refresh tokens are single-use. A request that tries to rotate a token someone else already
/// rotated fails with `400 invalid_request`, which is the bug users saw on Today.
private actor SingleUseTokenServer {
    private var tokenVersion = 0
    private var expired = true
    private(set) var rotations = 0
    private(set) var failures = 0

    func authorize() async throws {
        guard expired else { return }
        let presented = tokenVersion
        try await Task.sleep(for: .milliseconds(20)) // network round trip to WHOOP
        guard presented == tokenVersion else {
            failures += 1
            throw URLError(.userAuthenticationRequired) // reused refresh token
        }
        tokenVersion += 1
        rotations += 1
        expired = false
    }
}

private struct RaceyWhoopClient: WhoopClient {
    let server: SingleUseTokenServer

    func exchange(code: String, redirectURI: String) async throws {}
    func disconnect() async throws {}
    func isConnected() async throws -> Bool { true }
    func recoveries(since: Date) async throws -> [WhoopRecovery] { try await server.authorize(); return [] }
    func sleeps(since: Date) async throws -> [WhoopSleep] { try await server.authorize(); return [] }
    func cycles(since: Date) async throws -> [WhoopCycle] { try await server.authorize(); return [] }
    func workouts(since: Date?, maxRecords: Int) async throws -> [WhoopWorkout] { try await server.authorize(); return [] }
}

@MainActor
final class WhoopRefreshTests: XCTestCase {
    private func workoutStore() -> WorkoutStore {
        WorkoutStore(repository: MockWorkoutRepository(),
                     store: DraftStore(directory: FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)))
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(true, forKey: "whoop.historyImported") // skip the backfill here
    }

    func testExpiredTokenIsRotatedOnceAndSyncSucceeds() async {
        let server = SingleUseTokenServer()
        let whoop = WhoopStore(client: RaceyWhoopClient(server: server))
        await whoop.refresh(workouts: workoutStore())
        XCTAssertNil(whoop.errorMessage, "sync must not fail when the token has expired")
        let rotations = await server.rotations
        let failures = await server.failures
        XCTAssertEqual(rotations, 1)
        XCTAssertEqual(failures, 0, "no request may present an already-used refresh token")
    }

    func testOverlappingRefreshesShareOneSync() async {
        let server = SingleUseTokenServer()
        let whoop = WhoopStore(client: RaceyWhoopClient(server: server))
        let store = workoutStore()
        // Launch, foreground and pull-to-refresh can all fire at once.
        async let a: Void = whoop.refresh(workouts: store)
        async let b: Void = whoop.refresh(workouts: store)
        async let c: Void = whoop.refresh(workouts: store)
        _ = await (a, b, c)
        XCTAssertNil(whoop.errorMessage)
        let failures = await server.failures
        XCTAssertEqual(failures, 0)
    }
}
