import Foundation
import Combine
import ManagedSettings
#if canImport(WidgetKit)
import WidgetKit
#endif

// backed by app group defaults so the monitor extension and widget see same data
final class RunStore: ObservableObject {
    static let shared = RunStore()

    @Published private(set) var limits: [LimitConfig] = []
    @Published private(set) var dayState: DayState = .fresh()
    @Published private(set) var activeRun: ActiveRun?
    @Published var onboarded: Bool = false
    @Published var themeMode: ThemeMode = .system
    @Published private(set) var runMode: RunMode = .shared
    @Published private(set) var sharedRuns: Int = 4
    @Published private(set) var sharedUsed: Int = 0
    @Published private(set) var lockUntil: Date?       // nil = unlocked; .distantFuture = forever
    @Published private(set) var fullBlock: Bool = false // all apps 0 runs, emergency-only
    @Published private(set) var emergencyUses: [Date] = []  // spent emergencies, pruned to window
    @Published private(set) var breatheSeconds: Int = 5     // 0 = breathe off
    @Published private(set) var breatheSolo: Bool = false   // no budget, breathe only
    @Published private(set) var webBlocking: Bool = true
    @Published private(set) var platformOverrides: [String: Bool] = [:]
    @Published private(set) var pairedPlatformIDs: Set<String> = []
    @Published private(set) var platformPairs: [String: String] = [:]  // limitID -> platformID
    @Published private(set) var webDomainTokens: Set<WebDomainToken> = []
    @Published private(set) var webSessions: [String: Date] = [:]      // platformID -> endsAt
    @Published private(set) var customSites: [String] = []             // user-added domains
    @Published private(set) var webMinutes: [String: Int] = [:]        // platformID -> min/visit

    private let defaults = AppGroup.defaults

    private init() {
        load()
        rolloverIfNeeded()
        writeWidgetSnapshot()
    }

    func load() {
        limits = decode([LimitConfig].self, StoreKey.limits) ?? []
        dayState = decode(DayState.self, StoreKey.dayState) ?? .fresh()
        activeRun = decode(ActiveRun.self, StoreKey.activeRun)
        onboarded = defaults.bool(forKey: StoreKey.onboarded)
        themeMode = ThemeMode(rawValue: defaults.string(forKey: StoreKey.themeMode) ?? "") ?? .system
        runMode = RunMode(rawValue: defaults.string(forKey: StoreKey.runMode) ?? "") ?? .shared
        sharedRuns = defaults.object(forKey: StoreKey.sharedRuns) as? Int ?? 4
        sharedUsed = defaults.integer(forKey: StoreKey.sharedUsed)
        fullBlock = defaults.bool(forKey: StoreKey.fullBlock)
        breatheSeconds = defaults.object(forKey: StoreKey.breatheSeconds) as? Int ?? 5
        breatheSolo = defaults.bool(forKey: StoreKey.breatheSolo)
        webBlocking = defaults.object(forKey: StoreKey.webBlocking) as? Bool ?? true
        platformOverrides = defaults.dictionary(forKey: StoreKey.platformOverrides) as? [String: Bool] ?? [:]
        pairedPlatformIDs = WebPolicy.pairedPlatformIDs()
        platformPairs = defaults.dictionary(forKey: StoreKey.platformPairs) as? [String: String] ?? [:]
        webDomainTokens = decode(Set<WebDomainToken>.self, StoreKey.webDomainTokens) ?? []
        let sessions = defaults.dictionary(forKey: StoreKey.webSessions) as? [String: Double] ?? [:]
        webSessions = sessions.mapValues { Date(timeIntervalSince1970: $0) }
        customSites = defaults.stringArray(forKey: StoreKey.customSites) ?? []
        webMinutes = defaults.dictionary(forKey: StoreKey.webMinutes) as? [String: Int] ?? [:]
        loadEmergencies()
        loadLock()
    }

    // MARK: breathe + web blocking

    func setBreatheSeconds(_ seconds: Int) {
        breatheSeconds = seconds
        defaults.set(seconds, forKey: StoreKey.breatheSeconds)
    }

    // dropping the budget entirely is loosening, so solo can't be enabled while locked
    func setBreatheSolo(_ on: Bool) {
        if isLocked && on { return }
        breatheSolo = on
        defaults.set(on, forKey: StoreKey.breatheSolo)
        writeWidgetSnapshot()
    }

    // web blocking can be enabled anytime but only disabled while unlocked
    func setWebBlocking(_ on: Bool) {
        if isLocked && !on { return }
        webBlocking = on
        defaults.set(on, forKey: StoreKey.webBlocking)
    }

    // effective chip state: manual override wins, else auto-detected pairing
    func isPlatformBlocked(_ id: String) -> Bool {
        platformOverrides[id] ?? pairedPlatformIDs.contains(id)
    }

    func togglePlatform(_ id: String) {
        let current = isPlatformBlocked(id)
        if isLocked && current { return }   // unblocking a site while locked = loosening
        platformOverrides[id] = !current
        defaults.set(platformOverrides, forKey: StoreKey.platformOverrides)
    }

    // sites hand-picked in the picker's websites tab. while locked they can
    // only be added, mirroring setLimits
    func setWebDomainTokens(_ new: Set<WebDomainToken>) {
        if isLocked && !webDomainTokens.isSubset(of: new) { return }
        webDomainTokens = new
        encode(new, StoreKey.webDomainTokens)
    }

    // MARK: breathe-opened web sessions (chrome/brave have no extensions on iOS,
    // so the breathe happens in-app and grants the site a timed unblock)

    func pairedLimit(for platform: Platform) -> LimitConfig? {
        limits.first { platformPairs[$0.id.uuidString] == platform.id }
    }

    func webSessionEndsAt(_ platformID: String) -> Date? {
        guard let endsAt = webSessions[platformID], endsAt > Date() else { return nil }
        return endsAt
    }

    // site exception first (e.g. youtube 15), else the paired app's minutes
    func webSessionMinutes(for platform: Platform) -> Int {
        webMinutes[platform.id] ?? pairedLimit(for: platform)?.minutesPerRun ?? 3
    }

    // MARK: site rules (advanced: custom sites + minutes-per-visit exceptions)

    // more minutes per visit is loosening, blocked while locked; less is fine
    func setWebMinutes(_ platformID: String, minutes: Int) {
        let clamped = min(60, max(1, minutes))
        if isLocked, let platform = Platform.byID(platformID),
           clamped > webSessionMinutes(for: platform) { return }
        webMinutes[platformID] = clamped
        defaults.set(webMinutes, forKey: StoreKey.webMinutes)
    }

    // "youtube.com" from whatever was pasted: scheme/www/path stripped
    static func cleanDomain(_ raw: String) -> String? {
        var s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://", "www."] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
        }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        guard s.contains("."), !s.contains(" "), s.count >= 4 else { return nil }
        return s
    }

    func addCustomSite(_ raw: String) {
        guard let domain = Self.cleanDomain(raw), !customSites.contains(domain) else { return }
        customSites.append(domain)
        defaults.set(customSites, forKey: StoreKey.customSites)
    }

    func removeCustomSite(_ domain: String) {
        guard !isLocked else { return }   // unblocking a site while locked = loosening
        customSites.removeAll { $0 == domain }
        defaults.set(customSites, forKey: StoreKey.customSites)
    }

    // sessions are free (no run spent) but the budget still gates them: out of
    // runs means the web rests too. solo breathe has no budget at all.
    func canStartWebSession(for platform: Platform) -> Bool {
        if fullBlock { return false }
        if breatheSolo { return true }
        if let limit = pairedLimit(for: platform) { return runsLeft(for: limit) > 0 }
        return runMode == .shared ? max(0, sharedRuns - sharedUsed) > 0 : true
    }

    func beginWebSession(for platform: Platform) -> Date {
        let endsAt = Date().addingTimeInterval(TimeInterval(webSessionMinutes(for: platform) * 60))
        webSessions = webSessions.filter { $0.value > Date() }   // prune expired
        webSessions[platform.id] = endsAt
        defaults.set(webSessions.mapValues { $0.timeIntervalSince1970 }, forKey: StoreKey.webSessions)
        return endsAt
    }

    // MARK: full block + emergency allowance

    private func loadEmergencies() {
        let epochs = defaults.array(forKey: StoreKey.emergencyUses) as? [Double] ?? []
        emergencyUses = epochs.map { Date(timeIntervalSince1970: $0) }
        pruneEmergencies()
    }

    // uses still inside the rolling window. pure read (no mutation/persist) so it's
    // safe to call from SwiftUI body; the stored array is compacted separately.
    private var liveEmergencyUses: [Date] {
        let cutoff = Date().addingTimeInterval(-Emergency.windowSeconds)
        return emergencyUses.filter { $0 > cutoff }
    }

    // drop expired uses from storage. called at lifecycle points (load, spend),
    // never mid-render — reads use liveEmergencyUses instead to avoid publishing
    // a change from within a view update.
    private func pruneEmergencies() {
        let kept = liveEmergencyUses
        if kept.count != emergencyUses.count {
            emergencyUses = kept
            persistEmergencies()
        }
    }

    private func persistEmergencies() {
        defaults.set(emergencyUses.map(\.timeIntervalSince1970), forKey: StoreKey.emergencyUses)
    }

    // full block can only be turned ON while locked (tightening), never OFF
    func setFullBlock(_ on: Bool) {
        if isLocked && !on { return }
        fullBlock = on
        defaults.set(on, forKey: StoreKey.fullBlock)
        writeWidgetSnapshot()
    }

    var emergenciesLeft: Int {
        max(0, Emergency.total - liveEmergencyUses.count)
    }

    // when the oldest in-window use frees up, nil unless all are currently spent
    func nextEmergencyRefill() -> Date? {
        let live = liveEmergencyUses
        guard live.count >= Emergency.total, let oldest = live.min() else { return nil }
        return oldest.addingTimeInterval(Emergency.windowSeconds)
    }

    func canStartEmergency() -> Bool {
        activeRun == nil && emergenciesLeft > 0
    }

    // spend one emergency and open an all-apps run for Emergency.minutes.
    // no day/pool counter touched — the allowance is the only budget.
    func beginEmergencyRun() -> ActiveRun {
        rolloverIfNeeded()
        pruneEmergencies()
        let now = Date()
        emergencyUses.append(now)
        persistEmergencies()

        let run = ActiveRun(
            limitID: UUID(),                 // synthetic, not tied to a limit
            label: "EMERGENCY",
            startedAt: now,
            endsAt: now.addingTimeInterval(TimeInterval(Emergency.minutes * 60)),
            minutesPerRun: Emergency.minutes,
            isEmergency: true
        )
        activeRun = run
        persistActive()
        return run
    }

    // commitment lock invariant: while locked settings can only tighten, and the
    // lock extends only to a later date, never shortens. forever = .distantFuture,
    // only escape is deleting the app
    private func loadLock() {
        let t = defaults.double(forKey: StoreKey.lockUntil)
        guard t > 0 else { lockUntil = nil; return }
        // distantFuture epoch is enormous, treat anything past year ~4000 as forever
        lockUntil = t >= 64_000_000_000 ? .distantFuture : Date(timeIntervalSince1970: t)
    }

    var isLocked: Bool {
        guard let lockUntil else { return false }
        return lockUntil == .distantFuture || lockUntil > Date()
    }

    var isLockedForever: Bool { lockUntil == .distantFuture }

    // arm or extend the lock, ignores attempts to shorten/clear while locked
    func applyLock(_ duration: LockDuration) {
        guard let seconds = duration.seconds else {
            // .off only allowed while not already locked
            if !isLocked { clearLock() }
            return
        }
        let newUntil: Date = seconds.isInfinite
            ? .distantFuture
            : Date().addingTimeInterval(seconds)

        // can only move the unlock date later (tighten), never earlier
        if let current = lockUntil, isLocked {
            if current == .distantFuture { return }
            if newUntil != .distantFuture && newUntil <= current { return }
        }
        setLock(newUntil)
    }

    private func setLock(_ date: Date) {
        lockUntil = date
        let epoch = date == .distantFuture ? 64_000_000_000.0 : date.timeIntervalSince1970
        defaults.set(epoch, forKey: StoreKey.lockUntil)
    }

    private func clearLock() {
        lockUntil = nil
        defaults.removeObject(forKey: StoreKey.lockUntil)
    }

    func expireLockIfNeeded() {
        if let lockUntil, lockUntil != .distantFuture, lockUntil <= Date() {
            clearLock()
        }
    }

    func lockRemainingText() -> String {
        guard let lockUntil else { return "" }
        if lockUntil == .distantFuture { return "locked forever" }
        let secs = max(0, lockUntil.timeIntervalSinceNow)
        let days = Int(secs / 86_400)
        let hours = Int((secs.truncatingRemainder(dividingBy: 86_400)) / 3600)
        if days >= 1 { return "unlocks in \(days)d \(hours)h" }
        let mins = Int((secs.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours >= 1 { return "unlocks in \(hours)h \(mins)m" }
        return "unlocks in \(mins)m"
    }

    private func persistLimits() { encode(limits, StoreKey.limits); writeWidgetSnapshot() }
    private func persistDay() { encode(dayState, StoreKey.dayState); writeWidgetSnapshot() }
    private func persistActive() {
        if let activeRun { encode(activeRun, StoreKey.activeRun) }
        else { defaults.removeObject(forKey: StoreKey.activeRun) }
        writeWidgetSnapshot()
    }

    // token-free snapshot the home-screen widget can read, called on every
    // mutation so the widget never shows stale pips
    func writeWidgetSnapshot() {
        let items = limits.map { limit in
            WidgetSnapshot.Item(
                id: limit.id,
                label: limit.label.isEmpty ? "RUN" : limit.label,
                minutesPerRun: limit.minutesPerRun,
                runsLeft: runsLeft(for: limit),
                runsTotal: runsTotal(for: limit)
            )
        }
        let snapshot = WidgetSnapshot(
            items: items,
            activeLabel: activeRun.map { $0.label.isEmpty ? "RUN" : $0.label },
            activeEndsAt: activeRun?.endsAt,
            isPooled: runMode == .shared,
            poolLeft: fullBlock ? 0 : max(0, sharedRuns - sharedUsed),
            poolTotal: sharedRuns
        )
        encode(snapshot, StoreKey.widgetSnapshot)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    func rolloverIfNeeded() {
        let today = DayState.today()
        if dayState.day != today {
            dayState = DayState(day: today, runsUsed: [:])
            sharedUsed = 0
            defaults.set(0, forKey: StoreKey.sharedUsed)
            persistDay()
        }
    }

    // while locked callers may only tighten (add apps, lower minutes/runs).
    // these guards are the real enforcement, not the disabled UI controls
    func canRemove(_ limit: LimitConfig) -> Bool { !isLocked }

    func wouldLoosen(_ updated: LimitConfig) -> Bool {
        guard isLocked else { return false }
        guard let cur = limits.first(where: { $0.id == updated.id }) else {
            return false   // brand-new app = tightening
        }
        return updated.minutesPerRun > cur.minutesPerRun || updated.runsPerDay > cur.runsPerDay
    }

    func setLimits(_ new: [LimitConfig]) {
        if isLocked {
            let existing = Set(limits.map(\.id))
            let kept = Set(new.map(\.id))
            if !existing.isSubset(of: kept) { return }   // removal -> reject
        }
        limits = new
        persistLimits()
    }

    func upsert(_ limit: LimitConfig) {
        if wouldLoosen(limit) { return }
        if let i = limits.firstIndex(where: { $0.id == limit.id }) {
            limits[i] = limit
        } else {
            limits.append(limit)
        }
        persistLimits()
    }

    func remove(_ limit: LimitConfig) {
        guard canRemove(limit) else { return }
        limits.removeAll { $0.id == limit.id }
        dayState.runsUsed[limit.id] = nil
        persistLimits()
        persistDay()
    }

    func runsUsed(for limit: LimitConfig) -> Int {
        switch runMode {
        case .perApp: return dayState.runsUsed[limit.id] ?? 0
        case .shared: return sharedUsed
        }
    }

    func runsLeft(for limit: LimitConfig) -> Int {
        if fullBlock { return 0 }   // full block: normal runs disabled, emergency-only
        switch runMode {
        case .perApp: return max(0, limit.runsPerDay - (dayState.runsUsed[limit.id] ?? 0))
        case .shared: return max(0, sharedRuns - sharedUsed)
        }
    }

    func runsTotal(for limit: LimitConfig) -> Int {
        runMode == .shared ? sharedRuns : limit.runsPerDay
    }

    func canStartRun(for limit: LimitConfig) -> Bool {
        guard activeRun == nil else { return false }
        if breatheSolo && !fullBlock { return true }   // no budget in solo mode
        return runsLeft(for: limit) > 0
    }

    func beginRun(for limit: LimitConfig) -> ActiveRun {
        rolloverIfNeeded()
        // solo breathe has no budget, nothing to spend
        if !breatheSolo {
            switch runMode {
            case .perApp:
                dayState.runsUsed[limit.id] = (dayState.runsUsed[limit.id] ?? 0) + 1
                persistDay()
            case .shared:
                sharedUsed += 1
                defaults.set(sharedUsed, forKey: StoreKey.sharedUsed)
            }
        }

        let now = Date()
        let run = ActiveRun(
            limitID: limit.id,
            label: limit.label,
            startedAt: now,
            endsAt: now.addingTimeInterval(TimeInterval(limit.minutesPerRun * 60)),
            minutesPerRun: limit.minutesPerRun
        )
        activeRun = run
        persistActive()
        return run
    }

    func endRun() {
        activeRun = nil
        persistActive()
    }

    var completedRuns: Int { defaults.integer(forKey: StoreKey.completedRuns) }

    @discardableResult
    func recordCompletedRun() -> Int {
        let n = completedRuns + 1
        defaults.set(n, forKey: StoreKey.completedRuns)
        return n
    }

    // true exactly once, when crossing the 3-run mark and not yet asked
    func shouldRequestReviewNow() -> Bool {
        guard !defaults.bool(forKey: StoreKey.reviewAsked) else { return false }
        guard completedRuns >= 3 else { return false }
        defaults.set(true, forKey: StoreKey.reviewAsked)
        return true
    }

    func setOnboarded(_ value: Bool) {
        onboarded = value
        defaults.set(value, forKey: StoreKey.onboarded)
    }

    func setThemeMode(_ mode: ThemeMode) {
        themeMode = mode
        defaults.set(mode.rawValue, forKey: StoreKey.themeMode)
    }

    func setRunMode(_ mode: RunMode, sharedPool: Int = 4) {
        // changing mode or raising the pool while locked would loosen the commitment
        if isLocked {
            let sameMode = mode == runMode
            let poolNotRaised = mode == .shared ? sharedPool <= sharedRuns : true
            guard sameMode && poolNotRaised else { return }
        }
        runMode = mode
        sharedRuns = sharedPool
        defaults.set(mode.rawValue, forKey: StoreKey.runMode)
        defaults.set(sharedPool, forKey: StoreKey.sharedRuns)
        writeWidgetSnapshot()
    }

    private func encode<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
