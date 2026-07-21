import ManagedSettings
import DeviceActivity
import Foundation

// background process, CANNOT open URLs or launch apps (response is only
// .none/.close/.defer). but it CAN write the managed-settings store and start
// device-activity monitoring — which is exactly enough for breathe-to-open:
// TAKE A BREATH stashes a timestamp and defers (shield re-renders as the
// breathing pause), I'M READY after the pause spends a run, unshields the app,
// and arms the same re-lock ladder the app uses. early taps just defer again.
final class ShieldActionExtension: ShieldActionDelegate {

    // must match ShieldController.storeName / the monitor
    private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("runs.main"))
    private let center = DeviceActivityCenter()

    // must match ShieldState.sessionTimeout in the shield extension
    private let sessionTimeout: TimeInterval = 180

    override func handle(action: ShieldAction,
                         for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        let ctx = ActionStore()
        guard let limit = ctx.limit(for: application) else {
            completionHandler(.close)
            return
        }

        switch action {
        case .primaryButtonPressed:
            completionHandler(handlePrimary(ctx: ctx, limit: limit, token: application))
        case .secondaryButtonPressed:
            ctx.clearBreatheSession()
            completionHandler(.close)
        @unknown default:
            completionHandler(.close)
        }
    }

    private func handlePrimary(ctx: ActionStore,
                               limit: ActionStore.Limit,
                               token: ApplicationToken) -> ShieldActionResponse {
        // every state whose primary button reads OK/DISMISS lands here.
        // solo breathe has no budget, so the runs-left check only applies
        // when runs are the currency.
        guard ctx.breatheSeconds > 0,
              !ctx.fullBlock,
              !ctx.hasLiveRun(for: limit),
              !ctx.anyLiveRun,
              ctx.breatheSolo || ctx.runsLeft(for: limit) > 0
        else { return .close }

        // TAKE A BREATH — or a stale/foreign session — starts the pause
        guard let session = ctx.breatheSession,
              session.limitID == limit.id,
              Date().timeIntervalSince(session.startedAt) < sessionTimeout
        else {
            ctx.writeBreatheSession(for: limit)
            return .defer
        }

        // I'M READY too early: defer, the shield re-renders the seconds left
        guard Date().timeIntervalSince(session.startedAt) >= Double(ctx.breatheSeconds) else {
            return .defer
        }

        grantRun(ctx: ctx, limit: limit, token: token)
        return .none
    }

    // the breathe pause is served: start the run right here. same order rules
    // as the monitor — all synchronous writes before returning, store first.
    private func grantRun(ctx: ActionStore, limit: ActionStore.Limit, token: ApplicationToken) {
        let run = ctx.beginRun(for: limit)
        ctx.clearBreatheSession()

        var blocked = Set(ctx.limits.map(\.token))
        blocked.remove(token)
        store.shield.applications = blocked.isEmpty ? nil : blocked

        // the run frees the app AND its paired website together
        let domains = WebPolicy.blockedDomains(excludingLimitID: limit.id)
        store.webContent.blockedByFilter = domains.isEmpty
            ? nil
            : .specific(Set(domains.map { WebDomain(domain: $0) }))

        scheduleRunEnd(token: token, run: run)
    }

    // mirror of RunEngine.scheduleRunEnd/scheduleCeiling: a >=15-min outer
    // window carrying per-minute usage-threshold ticks (the monitor re-shields
    // once wall-clock endsAt passes) plus the guaranteed 15-min ceiling.
    private func scheduleRunEnd(token: ApplicationToken, run: ActionStore.ActiveRunDTO) {
        let runName = DeviceActivityName("runs.activeRun")
        let ceilingName = DeviceActivityName("runs.activeRun.ceiling")
        center.stopMonitoring([runName, ceilingName])

        let cal = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: cal.dateComponents([.hour, .minute, .second], from: run.startedAt),
            intervalEnd: cal.dateComponents([.hour, .minute, .second],
                                            from: run.startedAt.addingTimeInterval(16 * 60)),
            repeats: false
        )

        let lastMinute = max(run.minutesPerRun + 3, 4)
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for m in 1...lastMinute {
            events[DeviceActivityEvent.Name("runs.tick.\(m)")] = DeviceActivityEvent(
                applications: [token],
                threshold: DateComponents(minute: m)
            )
        }
        // best-effort: if scheduling fails the app's foreground reconcile and
        // BG refresh still end the run from the persisted endsAt
        try? center.startMonitoring(runName, during: schedule, events: events)

        let ceiling = DeviceActivitySchedule(
            intervalStart: cal.dateComponents([.hour, .minute, .second], from: run.startedAt),
            intervalEnd: cal.dateComponents([.hour, .minute, .second],
                                            from: run.startedAt.addingTimeInterval(15 * 60)),
            repeats: false
        )
        try? center.startMonitoring(ceilingName, during: ceiling)
    }

    override func handle(action: ShieldAction,
                         for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }

    override func handle(action: ShieldAction,
                         for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }
}
