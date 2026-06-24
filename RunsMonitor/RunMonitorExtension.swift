import DeviceActivity
import ManagedSettings
import FamilyControls
import ActivityKit
import Foundation

// out-of-process, reblocks every configured app when a window ends even if the
// app was killed; also does the midnight daily reset
final class RunMonitorExtension: DeviceActivityMonitor {

    // store name and group id must match the main app
    private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("runs.main"))
    private let defaults = UserDefaults(suiteName: "group.com.manif.runs")

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        if activity.rawValue == "runs.daily" {
            resetDailyCounters()
            return   // daily reset must not reblock/clear an in-progress run
        }

        endRunNow()
    }

    // usage-ladder tick: fires at each minute of foreground use. the THRESHOLD only
    // tells us "another minute of use elapsed" — the wall clock is the source of
    // truth. re-shield only once the run's endsAt has actually passed, so an early
    // tick (or the iOS 26 eager-fire bug) is harmless. once the user has been in the
    // app long enough, this lands within ~1 min of endsAt, silently, no tap/alarm.
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name,
                                         activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        if event.rawValue.hasPrefix("runs.tick.") {
            guard runIsOver() else { return }   // still within the run, keep ticking
        }
        endRunNow()
    }

    private func endRunNow() {
        // CRITICAL ORDER: write the shield SYNCHRONOUSLY first. iOS suspends this
        // extension the instant the user leaves, and endLiveActivities() blocks on a
        // semaphore — if it ran first and we got suspended mid-wait, the re-shield
        // would never happen and X would stay open. shield first, async teardown last.
        reblockAll()
        clearActiveRun()
        endLiveActivities()
    }

    // read the active run's wall-clock end from the shared App Group
    private func runEndsAt() -> Date? {
        guard let data = defaults?.data(forKey: "runs.activeRun.v1") else { return nil }
        struct RunDTO: Decodable { let endsAt: Date }
        return (try? JSONDecoder().decode(RunDTO.self, from: data))?.endsAt
    }

    // no active run persisted == nothing to protect, treat as over
    private func runIsOver() -> Bool {
        guard let endsAt = runEndsAt() else { return true }
        return Date() >= endsAt
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
    }

    // dismiss the run's Live Activity from out-of-process. the monitor is sync and
    // can be killed the instant it returns, so we hand the SYSTEM a near-future
    // dismissal deadline (.after) instead of .immediate: .immediate needs our async
    // call to fully land before the process dies (it often didn't, so the island
    // lingered at 0:00 until tapped), while .after lets iOS dismiss it on its own
    // even after we're gone. the brief semaphore wait just lets the end request reach
    // the daemon.
    private func endLiveActivities() {
        let activities = Activity<RunActivityAttributes>.activities
        guard !activities.isEmpty else { return }

        let now = Date()
        let final = RunActivityAttributes.ContentState(endsAt: now, startedAt: now)
        let dismissAt = now.addingTimeInterval(1)
        let sem = DispatchSemaphore(value: 0)
        Task {
            for activity in activities {
                await activity.end(
                    .init(state: final, staleDate: nil),
                    dismissalPolicy: .after(dismissAt)
                )
            }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 3)
    }

    private func reblockAll() {
        let tokens = configuredTokens()
        store.shield.applications = tokens.isEmpty ? nil : tokens
    }

    private func configuredTokens() -> Set<ApplicationToken> {
        guard let data = defaults?.data(forKey: "runs.limits.v1") else { return [] }
        guard let limits = try? JSONDecoder().decode([LimitConfigDTO].self, from: data) else { return [] }
        return Set(limits.map(\.token))
    }

    private func clearActiveRun() {
        defaults?.removeObject(forKey: "runs.activeRun.v1")
    }

    private func resetDailyCounters() {
        // write a fresh empty day, app reconciles exact date on next launch.
        // day string is device-local (Calendar.current + default TimeZone), matching
        // DayState.today() so the app doesn't re-roll on its next foreground.
        struct DayDTO: Encodable { let day: String; let runsUsed: [String: Int] }
        let f = DateFormatter()
        f.calendar = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let dto = DayDTO(day: f.string(from: Date()), runsUsed: [:])
        if let data = try? JSONEncoder().encode(dto) {
            defaults?.set(data, forKey: "runs.dayState.v1")
        }
        // shared mode is the default, so the per-app dayState reset above isn't enough:
        // the shared pool lives in its own key and must be zeroed too, or runs stay
        // exhausted until the app is next foregrounded.
        defaults?.set(0, forKey: "runs.sharedUsed.v1")
    }
}

// minimal mirror of LimitConfig, only the token is needed here
private struct LimitConfigDTO: Decodable {
    let token: ApplicationToken
}
