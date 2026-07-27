import Foundation

// shared across the app, widget, and monitor extension
enum AppGroup {
    static let id = "group.com.manif.runs"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }
}

enum StoreKey {
    static let limits = "runs.limits.v1"
    static let dayState = "runs.dayState.v1"
    static let activeRun = "runs.activeRun.v1"
    static let onboarded = "runs.onboarded.v1"
    static let themeMode = "runs.themeMode.v1"
    static let runMode = "runs.runMode.v1"
    static let sharedRuns = "runs.sharedRuns.v1"
    static let sharedUsed = "runs.sharedUsed.v1"
    static let completedRuns = "runs.completedRuns.v1"
    static let reviewAsked = "runs.reviewAsked.v1"
    static let lockUntil = "runs.lockUntil.v1"         // epoch; 0 = unlocked
    static let fullBlock = "runs.fullBlock.v1"         // bool; all apps 0 runs, emergency-only
    static let emergencyUses = "runs.emergencyUses.v1" // [Double] epochs of spent emergencies

    // written by the shield action extension on START A RUN tap, read + cleared
    // by the app on foreground since the shield process cant launch us itself
    static let shieldIntentToken = "runs.shieldIntent.tokenData.v1"
    static let shieldIntentAt = "runs.shieldIntent.at.v1"

    // breathe-to-open: 0 = off, otherwise seconds of pause the shield enforces
    static let breatheSeconds = "runs.breatheSeconds.v1"
    // bool: breathe stands alone — no run budget, every open is just one breath
    static let breatheSolo = "runs.breatheSolo.v1"
    // in-flight breathe pause {limitID, startedAt}, written by the shield action
    static let breatheSession = "runs.breatheSession.v1"

    // web blocking: bool (missing = on)
    static let webBlocking = "runs.webBlocking.v1"
    // auto-detected app<->site pairs, limitID uuid string -> platform id.
    // written by the shield extension the first time it renders for a known app
    static let platformPairs = "runs.platformPairs.v1"
    // manual per-platform toggles from settings, platform id -> bool
    static let platformOverrides = "runs.platformOverrides.v1"
    // websites hand-picked in the family activity picker (Set<WebDomainToken> json)
    static let webDomainTokens = "runs.webDomainTokens.v1"
    // live breathe-opened web sessions, platform id -> endsAt epoch. iOS chrome/
    // brave can't run extensions, so the breathe happens in the app and the
    // site unblocks here for its minutes
    static let webSessions = "runs.webSessions.v1"
    // user-added blocked sites beyond the catalog ([String] bare domains)
    static let customSites = "runs.customSites.v1"
    // per-site minutes-per-visit exceptions, platform id -> minutes
    // (e.g. youtube gets 15 while the default stays short)
    static let webMinutes = "runs.webMinutes.v1"
}
