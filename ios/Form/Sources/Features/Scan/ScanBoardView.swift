import PhotosUI
import SwiftUI
import VisionKit

/// One reviewed line, ready to become sets in a workout.
struct ScannedExercise {
    let exercise: Exercise
    let sets: Int
    let reps: Int?
    let seconds: Int?
    /// e.g. "Block A · each side"
    let note: String?
}

/// Snap a gym whiteboard → review what was read → hand the exercises back to the caller
/// (start a workout, or fill in a WHOOP session). Reading happens on-device; every line can be
/// re-matched or turned into a custom exercise.
struct ScanBoardView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Button title for a given number of exercises, e.g. "Start workout · 9".
    let confirmTitle: (Int) -> String
    /// Receives the board's title and the chosen exercises, just before the sheet dismisses.
    let onConfirm: (_ title: String, _ exercises: [ScannedExercise]) -> Void

    @State private var phase: Phase = .choose
    @State private var rows: [ReviewRow] = []
    @State private var title = ""
    @State private var photo: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var editing: ReviewRow.ID?
    @State private var creating: ReviewRow.ID?

    enum Phase: Equatable { case choose, reading, review, failed(String) }

    struct ReviewRow: Identifiable {
        let id = UUID()
        var line: PlannedLine
        var exercise: Exercise?
        var score: Double?
        var included = true
        var sets: Int
        var reps: Int?
        var seconds: Int?

        var confidence: ExerciseMatcher.Confidence { exercise == nil ? .none : ExerciseMatcher.confidence(score) }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .choose: chooser
                case .reading:
                    ProgressView("Reading the board…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .review: review
                case .failed(let message): failed(message)
                }
            }
            .background(Palette.bone)
            .navigationTitle(phase == .review ? "Review" : "Scan a board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if phase == .review {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Rescan") { phase = .choose; rows = [] }
                    }
                }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    phase = .reading
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        await read(image)
                    } else {
                        phase = .failed("Couldn't open that photo.")
                    }
                    photo = nil
                }
            }
            #if DEBUG
            .task {
                if phase == .choose, let path = DemoMode.scanImagePath, let image = UIImage(contentsOfFile: path) {
                    await read(image)
                }
            }
            #endif
            .fullScreenCover(isPresented: $showingCamera) {
                DocumentCamera { image in
                    showingCamera = false
                    if let image { Task { await read(image) } }
                }
                .ignoresSafeArea()
            }
            .sheet(item: Binding(get: { editing.flatMap { id in rows.firstIndex { $0.id == id } }.map { IndexBox(index: $0) } },
                                 set: { editing = $0.map { rows[$0.index].id } })) { box in
                ExerciseChoiceView(row: $rows[box.index])
            }
            .sheet(item: Binding(get: { creating.flatMap { id in rows.firstIndex { $0.id == id } }.map { IndexBox(index: $0) } },
                                 set: { creating = $0.map { rows[$0.index].id } })) { box in
                NewExerciseView(prefilledName: rows[box.index].line.name) { exercise in
                    rows[box.index].exercise = exercise
                    rows[box.index].score = 1
                    rows[box.index].included = true
                }
            }
        }
    }

    // MARK: Choose

    private var chooser: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "text.viewfinder")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(Palette.orange)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("SCAN THE BOARD").font(.cast(24)).foregroundStyle(Palette.ink)
                Text("Photograph the whiteboard. Form reads it on your phone, matches each line to an exercise, and you check it before starting.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.slateText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            Spacer()
            VStack(spacing: 12) {
                if VNDocumentCameraViewController.isSupported {
                    Button { showingCamera = true } label: {
                        Label("Scan with camera", systemImage: "camera.viewfinder")
                    }
                    .buttonStyle(PrimaryKeyStyle(height: 60))
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Choose a photo", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(Palette.ink)
                        .background(Palette.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Palette.rule, lineWidth: 1))
                }
            }
            .padding(20)
        }
    }

    private func failed(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Nothing to add", systemImage: "text.magnifyingglass")
        } description: {
            Text(message)
        } actions: {
            Button("Try again") { phase = .choose }
        }
    }

    // MARK: Reading

    private func read(_ image: UIImage) async {
        phase = .reading
        do {
            let lines = try await TextRecognizer.lines(in: image)
            let plan = BoardParser.parse(lines)
            guard !plan.lines.isEmpty else {
                phase = .failed("No exercises found. Try a straighter, closer photo of the board.")
                return
            }
            let matcher = ExerciseMatcher(exercises: store.library.all, remembered: BoardMemory.load())
            rows = plan.lines.map { line in
                let best = matcher.best(for: line.name)
                return ReviewRow(line: line, exercise: best?.exercise, score: best?.score,
                                 sets: line.sets ?? 3, reps: line.reps, seconds: line.seconds)
            }
            title = plan.title ?? ""
            phase = .review
        } catch {
            phase = .failed("Couldn't read the photo: \(error.localizedDescription)")
        }
    }

    // MARK: Review

    private var blocks: [(label: String?, indices: [Int])] {
        var result: [(label: String?, indices: [Int])] = []
        for index in rows.indices {
            let label = rows[index].line.block
            if let last = result.last, last.label == label {
                result[result.count - 1].indices.append(index)
            } else {
                result.append((label, [index]))
            }
        }
        return result
    }

    private var ready: [ReviewRow] { rows.filter { $0.included && $0.exercise != nil } }
    private var skipped: Int { rows.filter { $0.included && $0.exercise == nil }.count }

    private var review: some View {
        List {
            Section {
                TextField("Workout name", text: $title)
                    .font(.headline)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("Name").labelStyle()
            }
            .listRowBackground(Palette.card)

            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                Section {
                    ForEach(block.indices, id: \.self) { index in
                        reviewRow(index)
                    }
                } header: {
                    Text(block.label ?? "Exercises").labelStyle()
                }
                .listRowBackground(Palette.card)
            }
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) { startBar }
    }

    private func reviewRow(_ index: Int) -> some View {
        let row = rows[index]
        return HStack(alignment: .top, spacing: 10) {
            Button { rows[index].included.toggle() } label: {
                Image(systemName: row.included ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(row.included ? Palette.orange : Palette.rule)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.included ? "Included" : "Excluded")

            VStack(alignment: .leading, spacing: 6) {
                Button { editing = row.id } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.exercise?.name ?? "No match")
                                .font(.headline)
                                .foregroundStyle(row.exercise == nil ? Palette.orange : Palette.ink)
                            Text("“\(row.line.raw)”")
                                .font(.caption)
                                .foregroundStyle(Palette.slateText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.slateText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    Text(target(row))
                        .font(.caption.monospaced())
                        .foregroundStyle(Palette.slateText)
                    if row.confidence == .check {
                        Text("CHECK")
                            .font(.label)
                            .foregroundStyle(Palette.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.orange, lineWidth: 1))
                    }
                    Spacer(minLength: 0)
                    if row.exercise == nil || row.confidence == .check {
                        Button { creating = row.id } label: {
                            Label("Create", systemImage: "plus")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .frame(minHeight: 30)
                                .foregroundStyle(Palette.inkFixed)
                                .background(Palette.orange, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Create custom exercise \(row.line.name)")
                    }
                }
            }
            .opacity(row.included ? 1 : 0.5)
        }
        .padding(.vertical, 4)
    }

    private func target(_ row: ReviewRow) -> String {
        var parts = ["\(row.sets) sets"]
        if let seconds = row.seconds { parts.append("\(seconds)s") }
        if let reps = row.reps { parts.append(row.line.perSide ? "\(reps)/side" : "\(reps) reps") }
        return parts.joined(separator: " × ")
    }

    private var startBar: some View {
        VStack(spacing: 6) {
            if skipped > 0 {
                Text("\(skipped) line\(skipped == 1 ? "" : "s") without an exercise will be skipped")
                    .font(.caption)
                    .foregroundStyle(Palette.slateText)
            }
            Button(action: confirm) {
                Label(confirmTitle(ready.count), systemImage: "checkmark")
            }
            .buttonStyle(PrimaryKeyStyle(height: 60))
            .disabled(ready.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Palette.bone)
    }

    private func confirm() {
        let chosen = ready
        BoardMemory.remember(Dictionary(chosen.compactMap { row in row.exercise.map { (ExerciseMatcher.key(row.line.name), $0.id) } },
                                        uniquingKeysWith: { first, _ in first }))
        let exercises = chosen.compactMap { row -> ScannedExercise? in
            guard let exercise = row.exercise else { return nil }
            let note = [row.line.block, row.line.perSide ? "each side" : nil].compactMap { $0 }.joined(separator: " · ")
            return ScannedExercise(exercise: exercise, sets: row.sets, reps: row.reps, seconds: row.seconds,
                                   note: note.isEmpty ? nil : note)
        }
        onConfirm(title.trimmingCharacters(in: .whitespaces), exercises)
        dismiss()
    }
}

private struct IndexBox: Identifiable {
    let index: Int
    var id: Int { index }
}

/// Re-match one line: adjust the target, pick a suggestion, search, or create a custom exercise.
private struct ExerciseChoiceView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var row: ScanBoardView.ReviewRow

    @State private var query = ""
    @State private var creating = false
    @State private var created = false

    var body: some View {
        let matcher = ExerciseMatcher(exercises: store.library.all, remembered: BoardMemory.load())
        let suggestions = matcher.candidates(for: row.line.name, limit: 6).filter { $0.score >= 0.25 }
        NavigationStack {
            List {
                Section {
                    Text("“\(row.line.raw)”").foregroundStyle(Palette.slateText)
                    Stepper("Sets: \(row.sets)", value: $row.sets, in: 1...10)
                    if row.exercise?.metric == .duration {
                        Stepper("Hold: \(row.seconds ?? 30)s", value: Binding(get: { row.seconds ?? 30 }, set: { row.seconds = $0 }),
                                in: 5...600, step: 5)
                    } else {
                        Stepper("Reps: \(row.reps ?? 8)", value: Binding(get: { row.reps ?? 8 }, set: { row.reps = $0 }),
                                in: 1...100)
                    }
                } header: {
                    Text("Target").labelStyle()
                }

                Section {
                    Button { creating = true } label: {
                        Label("Create “\(row.line.name)”", systemImage: "plus.circle.fill")
                            .foregroundStyle(Palette.orange)
                    }
                } footer: {
                    Text("Adds it to your exercises so future scans match it automatically.")
                }

                if !suggestions.isEmpty && query.isEmpty {
                    Section {
                        ForEach(suggestions, id: \.exercise.id) { candidate in
                            choice(candidate.exercise)
                        }
                    } header: {
                        Text("Suggestions").labelStyle()
                    }
                }

                if !query.isEmpty {
                    Section {
                        ForEach(store.library.search(query).prefix(40)) { choice($0) }
                    } header: {
                        Text("All exercises").labelStyle()
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
            .navigationTitle("Pick exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $creating, onDismiss: { if created { dismiss() } }) {
                NewExerciseView(prefilledName: row.line.name) { exercise in
                    row.exercise = exercise
                    row.score = 1
                    row.included = true
                    created = true
                }
            }
        }
    }

    private func choice(_ exercise: Exercise) -> some View {
        Button {
            row.exercise = exercise
            row.score = 1
            row.included = true
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name).foregroundStyle(Palette.ink)
                    Text([exercise.bodyPart?.title, exercise.equipment?.capitalized].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Palette.slateText)
                }
                Spacer()
                if exercise.id == row.exercise?.id {
                    Image(systemName: "checkmark").foregroundStyle(Palette.orange)
                }
            }
        }
    }
}

/// VisionKit's document camera: edge detection and perspective correction, ideal for whiteboards.
private struct DocumentCamera: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish(scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onFinish(nil) }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFinish(nil)
        }
    }
}
