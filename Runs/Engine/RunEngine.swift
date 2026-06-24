import Foundation
import FamilyControls
import DeviceActivity
import ManagedSettings
import ActivityKit
import Combine

@MainActor
final class RunEngine: ObservableObject {
    static let shared = RunEngine()

    let store = RunStore.shared
    private let shield = ShieldController()
    private let center = DeviceActivityCenter()

    @Published var authorized = false
    @Published var authError: String?

    static let runActivityName = DeviceActivityName("runs.activeRun")
    // a separate 15-min window. the run window cant use a wall-clock schedule for
    // short runs (apple floors schedules at 15 min) so this is a guaranteed ceiling:
    // intervalDidEnd fires at the 15-min mark no matter what, capping the worst-case
    // overrun of a short backgrounded run at 15 min instead of indefinite.
    static let runCeilingName = DeviceActivityName("runs.activeRun.ceiling")
    static let dailyActivityName = DeviceActivityName("runs.daily")
    // usage-ladder tick events, one per minute of foreground use. the monitor checks
    // the wall clock on each and re-shields once the run's endsAt has passed.
    static func tickEvent(_ minute: Int) -> DeviceActivityEvent.Name {
        DeviceActivityEvent.Name("runs.tick.\(minute)")
    }
    static func isTickEvent(_ name: DeviceActivityEvent.Name) -> Bool {
        name.rawValue.hasPrefix("runs.tick.")
    }

    private var liveActivity: Activity<RunActivityAttributes>?

    private init() {}

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorized = AuthorizationCenter.shared.authorizationStatus == .approved
            authError = nil
        } catch {
            authorized = false
            authError = error.localizedDescription
        }
    }

    func refreshAuthorization() {
        authorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    // call on launch / whenever limits change
    func reapplyBaselineShield() {
        store.rolloverIfNeeded()
        endRunIfExpired()

        let all = Set(store.limits.map(\.token))
        let openToken: ApplicationToken? = store.activeRun.flatMap { run in
            store.limits.first { $0.id == run.limitID }?.token
        }
        shield.applyShield(allTokens: all, except: openToken)
        scheduleDailyReset()
    }

    // repeating daily window whose intervalDidEnd lands exactly at local midnight,
    // telling the monitor extension to wipe the run counters for the new day.
    // the window spans 00:01 -> 00:00(+1d) so intervalDidEnd fires AT 12am device
    // time, not 23:59 (which would reset a minute early, against the old day).
    // schedules are wall-clock against the device calendar/timezone, so this tracks
    // the user's local midnight and follows them across timezone changes.
    private func scheduleDailyReset() {
        guard !store.limits.isEmpty else {
            center.stopMonitoring([Self.dailyActivityName])
            return
        }
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 1),
            intervalEnd: DateComponents(hour: 0, minute: 0),
            repeats: true
        )
        do {
            try center.startMonitoring(Self.dailyActivityName, during: schedule)
        } catch {
            // non-fatal, app also resets on foreground via rolloverIfNeeded
        }
    }

    // widget tiles deep-link in as screenrun://run/<limitID> since the widget
    // process cant start a run itself, we start it here once foregrounded
    func handle(url: URL) {
        guard url.scheme == "screenrun", url.host == "run" else { return }

        let idString = url.lastPathComponent
        guard let id = UUID(uuidString: idString),
              let limit = store.limits.first(where: { $0.id == id })
        else { return }

        // reconcile day/expiry first so runsLeft is accurate
        store.rolloverIfNeeded()
        endRunIfExpired()
        if store.canStartRun(for: limit) {
            startRun(for: limit)
        }
    }

    // the shield used to stash a start-a-run intent that we consumed on foreground,
    // but the button is now DISMISS and no longer stashes. wipe any leftover stash
    // from before that change so it cant auto-start a run the user didnt ask for.
    func consumeShieldIntent() {
        let defaults = AppGroup.defaults
        defaults.removeObject(forKey: StoreKey.shieldIntentToken)
        defaults.removeObject(forKey: StoreKey.shieldIntentAt)
    }

    func startRun(for limit: LimitConfig) {
        guard store.canStartRun(for: limit) else { return }

        let run = store.beginRun(for: limit)

        let all = Set(store.limits.map(\.token))
        shield.applyShield(allTokens: all, except: limit.token)

        scheduleRunEnd(for: limit, run: run)
        startLiveActivity(for: limit, run: run)
    }

    func endRunNow() {
        guard store.activeRun != nil else { return }
        store.endRun()
        store.recordCompletedRun()
        center.stopMonitoring([Self.runActivityName, Self.runCeilingName])
        RunNotifier.cancelRunEnd()
        let all = Set(store.limits.map(\.token))
        shield.applyShield(allTokens: all, except: nil)
        Task { await endLiveActivity() }
    }

    // foregrounded after the timer already passed
    func endRunIfExpired() {
        if let run = store.activeRun, Date() >= run.endsAt {
            store.endRun()
            store.recordCompletedRun()
            // drop the run-end monitoring so a stale schedule cant fire into a
            // later run and reblock an app the user just opened
            center.stopMonitoring([Self.runActivityName, Self.runCeilingName])
            RunNotifier.cancelRunEnd()
                let all = Set(store.limits.map(\.token))
            shield.applyShield(allTokens: all, except: nil)
            Task { await endLiveActivity() }
        }
    }

    // Re-shield silently when the run is up, even while Runs is backgrounded/killed
    // and the user is heads-down scrolling the unshielded app. The mechanism that
    // actually works sub-15-min (a single DeviceActivitySchedule is floored at 15 min
    // and a single usage event only fires once) is a LADDER of usage-threshold events:
    //
    //   - one DeviceActivityEvent per minute of foreground usage (1, 2, … minutes).
    //     The system fires eventDidReachThreshold at EACH threshold as usage crosses
    //     it. For a user continuously in the app, usage-time ≈ wall-clock, so this
    //     ticks roughly once a wall-clock minute. On each tick the monitor compares
    //     Date() to the run's endsAt (read from the App Group) and re-shields once
    //     past — silent, no alarm, no tap. Re-adding the token covers the app the
    //     user is currently in (this is how one sec / ScreenZen re-lock mid-session).
    //   - the wall-clock comparison is the source of truth, never the event firing,
    //     so the iOS 26 "fires early" regression is harmless: an early tick just sees
    //     "not past endsAt yet" and does nothing.
    //   - extra minute-thresholds past minutesPerRun give a few more ticks so a
    //     dropped callback near the end still gets caught on the next minute of use.
    //
    // The 15-min ceiling schedule (scheduleCeiling) is the wall-clock backstop for the
    // idle/backgrounded case; the shield-config endsAt gate catches a re-open after
    // expiry; in-app timer + foreground reconcile remain.
    private func scheduleRunEnd(for limit: LimitConfig, run: ActiveRun) {
        let cal = Calendar.current
        let startComps = cal.dateComponents([.hour, .minute, .second], from: run.startedAt)
        // long outer window the usage events live inside. must be >= 15 min or iOS
        // rejects it ("schedule too short"); the events do the sub-15-min work.
        let endComps = cal.dateComponents([.hour, .minute, .second],
                                          from: run.startedAt.addingTimeInterval(16 * 60))
        let schedule = DeviceActivitySchedule(
            intervalStart: startComps,
            intervalEnd: endComps,
            repeats: false
        )

        // usage ladder: a tick at each minute of foreground use, a few past the
        // run length so late/dropped ticks still get a follow-up. 1-minute is the
        // reliable granularity floor for DeviceActivityEvent thresholds.
        let lastMinute = max(limit.minutesPerRun + 3, 4)
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for m in 1...lastMinute {
            events[Self.tickEvent(m)] = DeviceActivityEvent(
                applications: [limit.token],
                threshold: DateComponents(minute: m)
            )
        }

        do {
            try center.startMonitoring(Self.runActivityName, during: schedule, events: events)
        } catch {
            // best-effort, ceiling + foreground reconciliation still reblock
            print("device activity start failed: \(error)")
        }

        scheduleCeiling(from: run.startedAt)
        scheduleEndNotification(for: limit, run: run)
    }

    // guaranteed-ceiling window: exactly 15 min (apple's schedule floor) from run
    // start. for a short run this fires WELL after the real end, but it fires for
    // certain, capping a missed short run at 15 min instead of letting it run forever.
    private func scheduleCeiling(from start: Date) {
        let cal = Calendar.current
        let startComps = cal.dateComponents([.hour, .minute, .second], from: start)
        let endComps = cal.dateComponents([.hour, .minute, .second],
                                          from: start.addingTimeInterval(15 * 60))
        let schedule = DeviceActivitySchedule(
            intervalStart: startComps,
            intervalEnd: endComps,
            repeats: false
        )
        do {
            try center.startMonitoring(Self.runCeilingName, during: schedule)
        } catch {
            print("ceiling schedule failed: \(error)")
        }
    }

    // fires a buzz/alarm at the wall-clock end even for short runs (notifications
    // have no 15-min floor). it cant re-shield on its own, but it's time-sensitive
    // so it breaks through, and tapping it deep-links into Runs which re-locks.
    private func scheduleEndNotification(for limit: LimitConfig, run: ActiveRun) {
        RunNotifier.scheduleRunEnd(label: limit.label, at: run.endsAt)
    }

    private func startLiveActivity(for limit: LimitConfig, run: ActiveRun) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let liveLabel = limit.label.isEmpty ? "Run" : limit.label
        let attrs = RunActivityAttributes(
            appLabel: liveLabel,
            runsLeftAfter: store.runsLeft(for: limit)
        )
        let state = RunActivityAttributes.ContentState(endsAt: run.endsAt, startedAt: run.startedAt)
        do {
            liveActivity = try Activity.request(
                attributes: attrs,
                content: .init(state: state, staleDate: run.endsAt),
                pushType: nil
            )
        } catch {
            print("live activity start failed: \(error)")
        }
    }

    private func endLiveActivity() async {
        let now = Date()
        let final = RunActivityAttributes.ContentState(endsAt: now, startedAt: now)
        let dismissAt = now.addingTimeInterval(1)
        for activity in Activity<RunActivityAttributes>.activities {
            await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .after(dismissAt))
        }
        liveActivity = nil
    }
}
