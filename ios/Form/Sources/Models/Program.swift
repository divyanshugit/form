import Foundation

/// The plan: session templates, the weekly schedule per block, and double progression (goals.md §3).
enum Program {
    struct Slot: Hashable, Sendable {
        let ref: String
        let sets: Int
        let repMin: Int
        let repMax: Int
        /// Timed holds: target seconds instead of reps.
        var seconds: Int? = nil
        var note: String? = nil
    }

    enum TemplateID: String, CaseIterable, Identifiable, Sendable {
        case omniClass, afterClass, liftA, liftB, liftC, run, hyroxSim, travel, coreClass, rest
        var id: String { rawValue }
    }

    struct Template: Identifiable, Sendable {
        let id: TemplateID
        let name: String
        let summary: String
        let slots: [Slot]
        var symbol: String = "dumbbell"

        /// A template you start with exercises loaded (classes and runs are logged differently).
        var isLoggable: Bool { !slots.isEmpty }
    }

    static let templates: [TemplateID: Template] = {
        let list: [Template] = [
            Template(id: .omniClass, name: "Omni class", summary: "Full-body or core class. Scan the board when you get there.",
                     slots: [], symbol: "text.viewfinder"),
            Template(id: .afterClass, name: "After-class skill work", summary: "5–10 minutes: negatives, laterals, tuck holds.",
                     slots: [
                         Slot(ref: "Pullup_Negative", sets: 3, repMin: 3, repMax: 5, note: "3–5 s lowering"),
                         Slot(ref: "Side_Lateral_Raise", sets: 3, repMin: 12, repMax: 15),
                         Slot(ref: "Tuck_L_Sit", sets: 3, repMin: 0, repMax: 0, seconds: 15),
                     ], symbol: "figure.climbing"),
            Template(id: .liftA, name: "Lift A · leg-heavy", summary: "Squat, RDL + upper. L-sit and pull-up skill work.",
                     slots: [
                         Slot(ref: "Barbell_Squat", sets: 3, repMin: 8, repMax: 12),
                         Slot(ref: "Romanian_Deadlift", sets: 3, repMin: 8, repMax: 12),
                         Slot(ref: "Incline_Dumbbell_Press", sets: 3, repMin: 8, repMax: 12),
                         Slot(ref: "Bent_Over_Two-Dumbbell_Row", sets: 3, repMin: 8, repMax: 12),
                         Slot(ref: "Side_Lateral_Raise", sets: 4, repMin: 12, repMax: 15),
                         Slot(ref: "Pullup_Negative", sets: 3, repMin: 3, repMax: 5, note: "3–5 s lowering"),
                         Slot(ref: "Tuck_L_Sit", sets: 3, repMin: 0, repMax: 0, seconds: 20),
                     ]),
            Template(id: .liftB, name: "Lift B · full body", summary: "Deadlift, bench, pull-ups and dips.",
                     slots: [
                         Slot(ref: "Barbell_Deadlift", sets: 3, repMin: 5, repMax: 8),
                         Slot(ref: "Barbell_Bench_Press_-_Medium_Grip", sets: 3, repMin: 8, repMax: 12),
                         Slot(ref: "Pullups", sets: 3, repMin: 1, repMax: 8, note: "Strict. Negatives if no full rep yet"),
                         Slot(ref: "Dips_-_Triceps_Version", sets: 3, repMin: 6, repMax: 12),
                         Slot(ref: "Split_Squat_with_Dumbbells", sets: 3, repMin: 8, repMax: 12),
                         Slot(ref: "Side_Lateral_Raise", sets: 4, repMin: 12, repMax: 15),
                     ]),
            Template(id: .liftC, name: "Lift C · upper", summary: "Press, pull, arms. Explosive pulls and L-sit.",
                     slots: [
                         Slot(ref: "Standing_Military_Press", sets: 3, repMin: 8, repMax: 12),
                         Slot(ref: "Incline_Dumbbell_Press", sets: 3, repMin: 8, repMax: 12),
                         Slot(ref: "Wide-Grip_Lat_Pulldown", sets: 3, repMin: 8, repMax: 12),
                         Slot(ref: "Seated_Cable_Rows", sets: 3, repMin: 8, repMax: 12),
                         Slot(ref: "Side_Lateral_Raise", sets: 4, repMin: 12, repMax: 15),
                         Slot(ref: "Dumbbell_Alternate_Bicep_Curl", sets: 3, repMin: 10, repMax: 12),
                         Slot(ref: "Triceps_Pushdown_-_Rope_Attachment", sets: 3, repMin: 10, repMax: 12),
                         Slot(ref: "Explosive_Pullup", sets: 3, repMin: 3, repMax: 5),
                         Slot(ref: "L_Sit", sets: 3, repMin: 0, repMax: 0, seconds: 10),
                     ]),
            Template(id: .run, name: "Run", summary: "Mostly easy pace. +1 km every 2–3 weeks toward 10 km.",
                     slots: [], symbol: "figure.run"),
            Template(id: .hyroxSim, name: "HYROX sim (team)", summary: "Hard day. Log station splits after.",
                     slots: [], symbol: "flame.fill"),
            Template(id: .travel, name: "Travel routine", summary: "30–40 min, no gym. Don't lose ground.",
                     slots: [
                         Slot(ref: "Pushups", sets: 4, repMin: 10, repMax: 25, note: "Near failure. Feet up when easy"),
                         Slot(ref: "Pullup_Negative", sets: 3, repMin: 3, repMax: 5, note: "Any bar. Full pull-ups if you can"),
                         Slot(ref: "Split_Squat_with_Dumbbells", sets: 3, repMin: 10, repMax: 12, note: "Bulgarian or lunges, per leg"),
                         Slot(ref: "Pike_Pushup", sets: 3, repMin: 8, repMax: 10),
                         Slot(ref: "Plank", sets: 2, repMin: 0, repMax: 0, seconds: 45),
                         Slot(ref: "Tuck_L_Sit", sets: 2, repMin: 0, repMax: 0, seconds: 15),
                     ], symbol: "suitcase"),
            Template(id: .coreClass, name: "Core class or rest", summary: "Tuck L-sit holds if you rest.",
                     slots: [], symbol: "figure.core.training"),
            Template(id: .rest, name: "Rest", summary: "Walk if you like. Recovery is training.", slots: [], symbol: "bed.double"),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }()

    static func template(_ id: TemplateID) -> Template { templates[id]! }

    // MARK: Schedule

    /// The planned session for a date, by block and weekday (1 = Sunday … 7 = Saturday).
    static func planned(on date: Date, calendar: Calendar = .current) -> TemplateID {
        let weekday = calendar.component(.weekday, from: date)
        switch Goals.block(on: date).id {
        case .bali:
            switch weekday {
            case 2, 3, 4, 5: return .omniClass
            case 6: return .run
            case 7: return .hyroxSim
            default: return .rest
            }
        case .travel:
            switch weekday {
            case 2, 4, 6: return .travel
            case 3, 7: return .run
            default: return .rest
            }
        case .india:
            switch weekday {
            case 2: return .liftA
            case 3: return .coreClass
            case 4: return .liftB
            case 5: return .liftC
            case 6: return .run
            case 7: return .hyroxSim
            default: return .rest
            }
        }
    }

    /// Add-on skill work after Bali classes, 2–3 times a week (Mon, Wed, Thu).
    static func addOn(on date: Date, calendar: Calendar = .current) -> TemplateID? {
        guard Goals.block(on: date).id == .bali else { return nil }
        return [2, 4, 5].contains(calendar.component(.weekday, from: date)) ? .afterClass : nil
    }

    // MARK: Double progression

    struct Target: Equatable, Sendable {
        var weight: Double
        var reps: Int
        var seconds: Int?
        /// Why: "Hit 12 on every set last time → +2.5 kg".
        var reason: String?
    }

    /// Next session's target from last time. Hitting the top of the range on every set → add weight
    /// (2.5 kg on a barbell, 2 kg on dumbbells/machines) and drop back to the bottom of the range.
    static func target(for slot: Slot, metric: ExerciseMetric, kind: EquipmentKind, last: [SetRow]?) -> Target {
        let working = (last ?? []).filter { $0.kind != .warmup }
        if metric == .duration {
            let goal = slot.seconds ?? 30
            let best = working.map { $0.durationSeconds ?? 0 }.max() ?? 0
            guard best > 0 else { return Target(weight: 0, reps: 0, seconds: goal) }
            let allHit = working.count >= slot.sets && working.allSatisfy { ($0.durationSeconds ?? 0) >= goal }
            return allHit
                ? Target(weight: 0, reps: 0, seconds: best + 5, reason: "Held \(goal) s every set → +5 s")
                : Target(weight: 0, reps: 0, seconds: max(goal, best))
        }
        guard !working.isEmpty else {
            return Target(weight: metric == .weightReps ? (kind.barWeight ?? 0) : 0, reps: slot.repMin)
        }
        let weight = working.map { $0.weightKg ?? 0 }.max() ?? 0
        let atWeight = working.filter { ($0.weightKg ?? 0) >= weight }
        let allTop = working.count >= slot.sets && atWeight.count >= slot.sets
            && atWeight.allSatisfy { ($0.reps ?? 0) >= slot.repMax }

        if metric == .bodyweightReps {
            let best = working.map { $0.reps ?? 0 }.max() ?? 0
            return allTop
                ? Target(weight: weight, reps: slot.repMax, reason: "Top of the range on every set → add a rep or slow the lowering")
                : Target(weight: weight, reps: min(slot.repMax, max(slot.repMin, best + 1)))
        }

        guard weight > 0 else { return Target(weight: 0, reps: slot.repMin) }
        if allTop {
            let step = kind == .barbell || kind == .ezBar ? 2.5 : 2
            return Target(weight: weight + step, reps: slot.repMin,
                          reason: "\(slot.repMax) on every set last time → +\(step.kg) kg")
        }
        let reps = atWeight.map { $0.reps ?? 0 }.min() ?? slot.repMin
        return Target(weight: weight, reps: min(slot.repMax, max(slot.repMin, reps + 1)))
    }
}
