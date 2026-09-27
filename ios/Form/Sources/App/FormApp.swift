import SwiftUI

@main
struct FormApp: App {
    @State private var auth = AuthModel()
    @State private var whoop = WhoopStore()
    @State private var customExercises: CustomExerciseStore = {
        #if DEBUG
        if DemoMode.isOn {
            return CustomExerciseStore(repository: MockCustomExerciseRepository(),
                                       directory: FileManager.default.temporaryDirectory.appendingPathComponent("form-demo-custom"))
        }
        #endif
        return CustomExerciseStore()
    }()
    @State private var photos: PhotoStore = {
        #if DEBUG
        if DemoMode.isOn { return DemoMode.makePhotoStore() }
        #endif
        return PhotoStore()
    }()
    @State private var store: WorkoutStore = {
        #if DEBUG
        if DemoMode.isOn { return DemoMode.makeStore() }
        #endif
        return WorkoutStore()
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(store)
                .environment(whoop)
                .environment(photos)
                .environment(customExercises)
                .tint(Palette.denim)
                .task {
                    #if DEBUG
                    if DemoMode.isOn { return }
                    #endif
                    await auth.start()
                }
        }
    }
}

struct RootView: View {
    @Environment(AuthModel.self) private var auth

    var body: some View {
        #if DEBUG
        if DemoMode.isOn { return AnyView(MainTabView()) }
        #endif
        return AnyView(authGate)
    }

    @ViewBuilder
    private var authGate: some View {
        switch auth.state {
        case .loading:
            Palette.bone.ignoresSafeArea()
        case .signedOut:
            SignInView()
        case .signedIn:
            MainTabView()
        }
    }
}

struct MainTabView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(WhoopStore.self) private var whoop
    @Environment(PhotoStore.self) private var photos
    @Environment(CustomExerciseStore.self) private var customExercises
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingWorkout = false
    @State private var tab: Int = {
        #if DEBUG
        return DemoMode.tab
        #else
        return 0
        #endif
    }()

    var body: some View {
        TabView(selection: $tab) {
            TodayView(showingWorkout: $showingWorkout)
                .tag(0)
                .tabItem { Label("Today", systemImage: "house") }
            HistoryView()
                .tag(1)
                .tabItem { Label("History", systemImage: "calendar") }
            BodyView(showingWorkout: $showingWorkout)
                .tag(2)
                .tabItem { Label("Body", systemImage: "figure.strengthtraining.traditional") }
            PhotosView()
                .tag(3)
                .tabItem { Label("Photos", systemImage: "camera") }
            ComingSoonView(title: "Journal", systemImage: "book.closed",
                           message: "Notes, mood and body weight. Coming in the photo build.")
                .tag(4)
                .tabItem { Label("Journal", systemImage: "book.closed") }
        }
        .fullScreenCover(item: Binding(
            get: { showingWorkout ? store.active : nil },
            set: { if $0 == nil { showingWorkout = false } }
        )) { active in
            ActiveWorkoutView(workout: active)
        }
        .task {
            await customExercises.refresh()
            await store.refresh()
            #if DEBUG
            DemoMode.prepareWorkout(in: store)
            if DemoMode.isOn { whoop.loadDemo() }
            #endif
            // Reopen straight into a workout that was interrupted (app killed mid-session).
            if store.active != nil { showingWorkout = true }
            #if DEBUG
            if DemoMode.isOn { return }
            #endif
            await photos.refresh()
            await whoop.refresh(workouts: store)
        }
        .onChange(of: scenePhase) { _, phase in
            // WHOOP scores workouts a few minutes after they end; re-sync whenever the app comes back.
            guard phase == .active else { return }
            #if DEBUG
            if DemoMode.isOn { return }
            #endif
            Task {
                await customExercises.sync()
                await store.refresh()
                await photos.sync()
                await whoop.refresh(workouts: store)
            }
        }
    }
}
