import SwiftUI
import BackgroundTasks

@main
struct RunsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var engine = RunEngine.shared
    @StateObject private var store = RunStore.shared

    // background wake to reconcile an expired run. iOS decides exactly when this
    // runs (not guaranteed at endsAt) but it's another net for a short run that
    // expired while Runs was backgrounded.
    static let refreshTaskID = "com.manif.runs.refresh"

    init() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskID,
            using: nil
        ) { task in
            RunEngine.shared.reapplyBaselineShield()   // ends expired runs
            RunsApp.scheduleRefresh()                  // chain the next wake
            task.setTaskCompleted(success: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .environmentObject(store)
                .preferredColorScheme(store.themeMode.colorScheme)
                .onAppear {
                    engine.refreshAuthorization()
                    RunNotifier.requestAuthorization()
                    // pending shield START A RUN tap waiting from another process
                    engine.consumeShieldIntent()
                    engine.reapplyBaselineShield()
                }
                .onOpenURL { url in
                    engine.handle(url: url)
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                engine.store.rolloverIfNeeded()
                engine.store.expireLockIfNeeded()
                engine.refreshAuthorization()
                engine.consumeShieldIntent()
                engine.reapplyBaselineShield()   // also ends expired runs
            } else if phase == .background {
                RunsApp.scheduleRefresh()
            }
        }
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        // ask for the soonest wake iOS will grant; it throttles to its own cadence
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
