import Foundation
import UserNotifications

/// Gentle local reminders, rescheduled every time the app comes forward:
/// - no session logged by a couple of hours after the usual time (on a planned training day)
/// - Sunday evening: the week is ready to review and share
/// - photo day, four weeks after the last progress photo
enum Nudges {
    static let sessionID = "nudge.session"
    static let weeklyID = "nudge.weekly"
    static let photoID = "nudge.photo"

    /// The hour sessions usually start, from the last 30 (median), defaulting to 5 pm.
    static func usualHour(_ history: [WorkoutRow], calendar: Calendar = .current) -> Int {
        let hours = Momentum.training(history).prefix(30).map { calendar.component(.hour, from: $0.startedAt) }.sorted()
        return hours.isEmpty ? 17 : hours[hours.count / 2]
    }

    /// When to nudge for a missing session: today at usual + 2 h if nothing is logged and it's still ahead,
    /// otherwise the next planned training day. Pure.
    static func nextSessionNudge(history: [WorkoutRow], now: Date, calendar: Calendar = .current) -> Date? {
        let hour = min(21, usualHour(history, calendar: calendar) + 2)
        for offset in 0..<7 {
            let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
            guard Program.planned(on: day, calendar: calendar) != .rest else { continue }
            let trained = Momentum.training(history).contains { calendar.isDate($0.startedAt, inSameDayAs: day) }
            if offset == 0 && trained { continue }
            let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
            if fire > now { return fire }
        }
        return nil
    }

    @MainActor
    static func reschedule(history: [WorkoutRow], photos: [ProgressPhoto], now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        center.removePendingNotificationRequests(withIdentifiers: [sessionID, weeklyID, photoID])
        let calendar = Calendar.current

        if let fire = nextSessionNudge(history: history, now: now) {
            let template = Program.template(Program.planned(on: fire))
            let week = Momentum.week(containing: fire, history: history)
            let content = UNMutableNotificationContent()
            content.title = "Today: \(template.name)"
            content.body = "\(week.daysTrained) of \(week.target) days this week. One session keeps the streak alive."
            content.sound = .default
            await add(center, sessionID, content, calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
        }

        let weekly = UNMutableNotificationContent()
        weekly.title = "Your week is ready"
        weekly.body = "See what the numbers say, then share the week."
        weekly.sound = .default
        await add(center, weeklyID, weekly, DateComponents(hour: 18, minute: 0, weekday: 1), repeats: true)

        if let last = photos.map(\.takenAt).max() {
            var due = calendar.date(byAdding: .day, value: 28, to: calendar.startOfDay(for: last))!
            if due <= now { due = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))! }
            let photo = UNMutableNotificationContent()
            photo.title = "Photo day"
            photo.body = "Same spot, same light, morning. Front, side and back."
            photo.sound = .default
            var parts = calendar.dateComponents([.year, .month, .day], from: due)
            parts.hour = 8
            await add(center, photoID, photo, parts, repeats: false)
        }
    }

    private static func add(_ center: UNUserNotificationCenter, _ id: String, _ content: UNNotificationContent,
                            _ components: DateComponents, repeats: Bool) async {
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
