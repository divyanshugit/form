import AuthenticationServices
import Foundation
import Supabase
import SwiftUI

/// WHOOP connection state, today's recovery and sleep, and workout sync.
@MainActor
@Observable
final class WhoopStore {
    private(set) var isConnected = false
    private(set) var recovery: WhoopRecovery?
    private(set) var sleep: WhoopSleep?
    /// Last 30 days, oldest first.
    private(set) var days: [WhoopDay] = []
    /// WHOOP workouts/activities in the last 30 days, newest first.
    private(set) var activities: [WhoopWorkout] = []
    private(set) var isBusy = false
    private(set) var isImportingHistory = false
    /// One-line result of the last history import, shown in History.
    private(set) var historyStatus: String?
    var errorMessage: String?

    private static let backfillKey = "whoop.historyImported"
    /// The refresh in flight. WHOOP refresh tokens are single-use, so overlapping syncs
    /// would each try to rotate the same token and all but one would fail.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    static let windowDays = 30
    /// Set after a successful connect so the next view refresh syncs immediately.
    var justConnected = false

    private let client: WhoopClient

    init(client: WhoopClient = SupabaseWhoopClient()) {
        self.client = client
    }

    var recoveryScore: Double? { recovery?.score?.recoveryScore }

    // MARK: Connect

    func connect(using session: WebAuthenticationSession) async {
        errorMessage = nil
        let state = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        do {
            let callback = try await session.authenticate(
                using: WhoopConfig.authorizeURL(state: state),
                callbackURLScheme: WhoopConfig.callbackScheme,
                preferredBrowserSession: .ephemeral
            )
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard items.first(where: { $0.name == "state" })?.value == state,
                  let code = items.first(where: { $0.name == "code" })?.value else {
                errorMessage = items.first(where: { $0.name == "error_description" })?.value
                    ?? "WHOOP didn't return a sign-in code."
                return
            }
            isBusy = true
            defer { isBusy = false }
            try await client.exchange(code: code, redirectURI: WhoopConfig.redirectURI)
            isConnected = true
            justConnected = true
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch {
            errorMessage = "Couldn't connect WHOOP: \(Self.describe(error))"
        }
    }

    func disconnect() async {
        try? await client.disconnect()
        UserDefaults.standard.removeObject(forKey: Self.backfillKey)
        isConnected = false
        recovery = nil
        sleep = nil
        days = []
        activities = []
    }

    // MARK: Refresh

    /// Pulls recovery + sleep, then attaches WHOOP workouts to Form sessions and imports WHOOP-only ones.
    /// Single-flight: a second caller waits for the refresh already running instead of starting another.
    func refresh(workouts: WorkoutStore) async {
        if let running = refreshTask {
            await running.value
            return
        }
        let task = Task { await performRefresh(workouts: workouts) }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh(workouts: WorkoutStore) async {
        do {
            isConnected = try await client.isConnected()
        } catch {
            return // offline or not signed in; keep whatever we had
        }
        guard isConnected else { return }
        let since = Calendar.current.date(byAdding: .day, value: -Self.windowDays, to: .now)!
        do {
            // One call first: if the access token has expired, this is the only request that
            // rotates it. The parallel calls after it all reuse the fresh token.
            let r = try await client.recoveries(since: since)
            async let sleepList = client.sleeps(since: since)
            async let cycleList = client.cycles(since: since)
            async let workoutList = client.workouts(since: since, maxRecords: 400)
            let (sl, c, w) = try await (sleepList, cycleList, workoutList)

            recovery = r.filter { $0.scoreState == .scored }.max { $0.createdAt < $1.createdAt }
            sleep = sl.filter { !$0.nap && $0.scoreState == .scored }.max { $0.end < $1.end }
            days = WhoopDay.build(cycles: c, recoveries: r, sleeps: sl)
            activities = w.filter { $0.scoreState == .scored }.sorted { $0.start > $1.start }

            let plan = WhoopMatching.plan(formWorkouts: workouts.history, whoop: w)
            if let failure = await workouts.apply(plan) {
                errorMessage = "Couldn't save WHOOP activities: \(failure)"
            } else {
                errorMessage = nil
            }
        } catch {
            errorMessage = "WHOOP sync failed: \(Self.describe(error))"
            return
        }
        // First sync after connecting: pull the whole WHOOP history once.
        if !UserDefaults.standard.bool(forKey: Self.backfillKey) {
            await importHistory(workouts: workouts)
        }
    }

    /// Walks every WHOOP workout ever recorded. Matching Form sessions get WHOOP data attached;
    /// everything else is imported. Idempotent: imports are keyed by WHOOP's own workout id.
    func importHistory(workouts: WorkoutStore) async {
        guard isConnected, !isImportingHistory else { return }
        isImportingHistory = true
        historyStatus = "Importing your WHOOP history…"
        defer { isImportingHistory = false }
        do {
            let all = try await client.workouts(since: nil, maxRecords: 5000)
            let plan = WhoopMatching.plan(formWorkouts: workouts.history, whoop: all)
            if let failure = await workouts.apply(plan) {
                historyStatus = "History import stopped: \(failure). Try again from History."
                return
            }
            UserDefaults.standard.set(true, forKey: Self.backfillKey)
            let oldest = all.map(\.start).min()
            historyStatus = "WHOOP history in"
                + (oldest.map { " back to \($0.formatted(.dateTime.month(.abbreviated).year()))" } ?? "")
                + ": \(plan.attach.count) matched to your sessions, \(plan.imports.count) new activities."
            await workouts.refresh()
        } catch {
            historyStatus = "History import stopped: \(Self.describe(error)). Try again from History."
        }
    }

    /// Surfaces the edge function's own error text (e.g. "WHOOP token error 401: invalid_client").
    static func describe(_ error: Error) -> String {
        if case let FunctionsError.httpError(code, data) = error {
            struct Body: Decodable { let error: String? }
            let message = (try? JSONDecoder().decode(Body.self, from: data))?.error
            return message.map { "\($0) (\(code))" } ?? "server returned \(code)"
        }
        return error.localizedDescription
    }

    #if DEBUG
    func loadDemo() {
        isConnected = true
        recovery = WhoopRecovery(
            cycleId: 1, sleepId: nil, createdAt: .now, scoreState: .scored,
            score: .init(recoveryScore: 82, restingHeartRate: 54, hrvRmssdMilli: 72, userCalibrating: false)
        )
        let end = Calendar.current.date(bySettingHour: 6, minute: 50, second: 0, of: .now)!
        sleep = WhoopSleep(
            id: "demo", cycleId: nil, start: end.addingTimeInterval(-8.2 * 3600), end: end, nap: false, scoreState: .scored,
            score: .init(stageSummary: .init(totalInBedTimeMilli: 8.2 * 3_600_000, totalAwakeTimeMilli: 0.5 * 3_600_000),
                         sleepPerformancePercentage: 91)
        )
        let calendar = Calendar.current
        days = (0..<30).map { offset in
            let date = calendar.date(byAdding: .day, value: offset - 29, to: .now)!
            let wave = sin(Double(offset) / 3)
            return WhoopDay(id: offset, date: date, recovery: max(18, min(97, 62 + wave * 25 + Double(offset % 5) * 3)),
                            hrv: 60 + wave * 12, restingHeartRate: 55 - wave * 3, sleepHours: 7 + wave * 0.9,
                            dayStrain: 8 + Double((offset * 7) % 9), kcal: 2300 + (offset * 37) % 700,
                            averageHeartRate: 68 + offset % 8)
        }
    }
    #endif
}
