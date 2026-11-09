import PhotosUI
import SwiftUI

/// Backfill classes from a batch of whiteboard photos. Each photo is dated from its EXIF, matched to the
/// session logged at that time (usually a WHOOP import), read, reviewed, and saved onto that session.
struct BoardImportView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var picked: [PhotosPickerItem] = []
    @State private var jobs: [Job] = []
    @State private var isLoading = false
    @State private var scanning: Scan?
    @State private var lastScan: Scan?

    struct Job: Identifiable {
        let id = UUID()
        let item: PhotosPickerItem
        var takenAt: Date?
        var sessionID: UUID?
        var status: Status = .waiting

        enum Status: Equatable { case waiting, saved(Int), skipped, failed(String) }
    }

    /// The board currently open in the scanner.
    struct Scan: Identifiable {
        let id = UUID()
        let jobID: UUID
        let image: UIImage
        let subtitle: String
    }

    private var pending: [Job] { jobs.filter { $0.status == .waiting && $0.sessionID != nil } }

    var body: some View {
        NavigationStack {
            List {
                if jobs.isEmpty {
                    intro
                } else {
                    Section {
                        ForEach(jobs) { job in row(job) }
                    } header: {
                        Text("\(jobs.count) board\(jobs.count == 1 ? "" : "s") · oldest first").labelStyle()
                    } footer: {
                        Text("Weights start empty: boards don't say what you lifted. Fill in the ones you remember from History.")
                    }
                    .listRowBackground(Palette.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bone)
            .navigationTitle("Import boards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                Task { await load(items) }
            }
            .sheet(item: $scanning, onDismiss: { advance() }) { scan in
                ScanBoardView(
                    confirmTitle: { "Save \($0) exercise\($0 == 1 ? "" : "s")" },
                    onConfirm: { title, exercises in
                        Task { await save(jobID: scan.jobID, title: title, exercises: exercises) }
                    },
                    initialImage: scan.image,
                    subtitle: scan.subtitle
                )
            }
        }
    }

    // MARK: Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Palette.orange)
            Text("BACKFILL YOUR CLASSES").font(.cast(22)).foregroundStyle(Palette.ink)
            Text("Pick the whiteboard photos from past classes. Form dates each one from the photo, finds the session WHOOP logged at that time, reads the board, and lets you check it before saving.")
                .font(.subheadline)
                .foregroundStyle(Palette.slateText)
        }
        .padding(.vertical, 12)
        .listRowBackground(Color.clear)
    }

    private func row(_ job: Job) -> some View {
        let session = job.sessionID.flatMap { id in store.history.first { $0.id == id } }
        return HStack(spacing: 12) {
            statusIcon(job)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.takenAt?.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()) ?? "No date in photo")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Group {
                    switch job.status {
                    case .saved(let count): Text("\(session?.name ?? "Session") · \(count) exercise\(count == 1 ? "" : "s") saved")
                    case .skipped: Text("Skipped")
                    case .failed(let message): Text(message)
                    case .waiting:
                        if let session {
                            Text(session.sortedExercises.isEmpty ? session.name : "\(session.name) · already has exercises")
                        } else {
                            Text(job.takenAt == nil ? "Can't match without a date" : "No session logged at this time")
                        }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Palette.slateText)
            }
            Spacer(minLength: 0)
            if job.status == .waiting, job.sessionID != nil {
                Button("Scan") { open(job.id) }
                    .font(.subheadline.weight(.bold))
                    .buttonStyle(.borderless)
                    .tint(Palette.orange)
            }
        }
        .padding(.vertical, 4)
        .swipeActions {
            if job.status == .waiting {
                Button("Skip") { set(job.id, .skipped) }.tint(Palette.slateText)
            }
        }
    }

    private func statusIcon(_ job: Job) -> some View {
        let (name, color): (String, Color) = switch job.status {
        case .saved: ("checkmark.circle.fill", Palette.orange)
        case .skipped: ("minus.circle", Palette.rule)
        case .failed: ("exclamationmark.circle", Palette.orange)
        case .waiting: (job.sessionID == nil ? "questionmark.circle" : "circle", Palette.slateText)
        }
        return Image(systemName: name).font(.title3).foregroundStyle(color).frame(width: 28)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if isLoading {
                ProgressView("Reading photo dates…")
            } else if jobs.isEmpty {
                PhotosPicker(selection: $picked, maxSelectionCount: 60, matching: .images) {
                    Label("Choose board photos", systemImage: "photo.on.rectangle.angled")
                }
                .buttonStyle(PrimaryKeyStyle(height: 60))
            } else if let next = pending.first {
                Button { open(next.id) } label: {
                    Label("Scan next · \(pending.count) left", systemImage: "text.viewfinder")
                }
                .buttonStyle(PrimaryKeyStyle(height: 60))
            } else {
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryKeyStyle(height: 60))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Palette.bone)
    }

    // MARK: Flow

    /// Reads each photo's date (loading one at a time, so 60 MB RAW files never pile up), then matches sessions.
    private func load(_ items: [PhotosPickerItem]) async {
        isLoading = true
        var loaded: [Job] = []
        for item in items {
            let data = try? await item.loadTransferable(type: Data.self)
            let date = data.flatMap(BoardImport.takenAt)
            let session = date.flatMap { BoardImport.session(for: $0, in: store.history) }
            loaded.append(Job(item: item, takenAt: date, sessionID: session?.id))
        }
        jobs = loaded.sorted { ($0.takenAt ?? .distantFuture) < ($1.takenAt ?? .distantFuture) }
        picked = []
        isLoading = false
    }

    private func open(_ jobID: UUID) {
        guard let job = jobs.first(where: { $0.id == jobID }),
              let session = job.sessionID.flatMap({ id in store.history.first { $0.id == id } }) else { return }
        let position = (jobs.firstIndex { $0.id == jobID } ?? 0) + 1
        Task {
            guard let data = try? await job.item.loadTransferable(type: Data.self),
                  let image = BoardImport.image(data) else {
                set(jobID, .failed("Couldn't open the photo"))
                return
            }
            let when = session.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute())
            let scan = Scan(jobID: jobID, image: image, subtitle: "Board \(position) of \(jobs.count) · \(when) · \(session.name)")
            lastScan = scan
            scanning = scan
        }
    }

    /// After a board is saved, open the next one automatically; after a cancel, stay on the list.
    @State private var autoAdvance = false

    private func advance() {
        guard autoAdvance, let next = pending.first else { return }
        autoAdvance = false
        open(next.id)
    }

    private func save(jobID: UUID, title: String, exercises: [ScannedExercise]) async {
        guard let job = jobs.first(where: { $0.id == jobID }),
              let session = job.sessionID.flatMap({ id in store.history.first { $0.id == id } }) else { return }
        var draft = WorkoutDraft(
            id: session.id,
            name: BoardImport.name(current: session.name, original: session.name,
                                   isWhoopImport: session.isWhoopImport, boardTitle: title),
            startedAt: session.startedAt, endedAt: session.endedAt
        )
        draft.notes = session.notes
        draft.exercises = existingExercises(session) + exercises.map {
            BoardImport.plannedExercise($0.exercise, sets: $0.sets, reps: $0.reps, seconds: $0.seconds,
                                        note: $0.note, at: session.startedAt)
        }
        await store.update(draft, keeping: session)
        if let scan = scanning ?? lastScan, scan.jobID == jobID { BoardPhotos.save(scan.image, for: session.id) }
        set(jobID, .saved(exercises.count))
        autoAdvance = true
    }

    private func existingExercises(_ session: WorkoutRow) -> [DraftExercise] {
        session.sortedExercises.map { row in
            DraftExercise(id: row.id, exerciseRef: row.exerciseRef, sets: row.sortedSets.map { set in
                DraftSet(id: set.id, kind: set.kind, weight: set.weightKg ?? 0, reps: set.reps ?? 0,
                         completedAt: set.completedAt ?? session.startedAt, durationSeconds: set.durationSeconds)
            }, notes: row.notes)
        }
    }

    private func set(_ jobID: UUID, _ status: Job.Status) {
        if let i = jobs.firstIndex(where: { $0.id == jobID }) { jobs[i].status = status }
    }
}
