import Foundation

/// Names for WHOOP-imported sessions that say what the session really was.
enum SessionNaming {
    static let hyroxSim = "HYROX sim (team)"

    /// Saturday-morning "Functional Fitness" is the team HYROX simulation.
    static func isHyroxSim(sportName: String, start: Date, calendar: Calendar = .current) -> Bool {
        guard sportName == "Functional Fitness" else { return false }
        let parts = calendar.dateComponents([.weekday, .hour], from: start)
        return parts.weekday == 7 && (5..<12).contains(parts.hour ?? 0)
    }
}
