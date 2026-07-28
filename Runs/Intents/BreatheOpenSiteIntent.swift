import AppIntents
import Foundation

// unlocking a site from OUTSIDE the app. brave and chrome on iOS can't host our
// breathe wall (no extension support, and no app may draw into another), so
// this intent is the wall: it holds you for the same seconds the wall would,
// then grants the site its minutes. put it in Control Center, on the Action
// Button, or on a Back Tap and the whole breathe happens without leaving the
// browser.

struct SiteEntity: AppEntity {
    let id: String
    let name: String

    init(_ platform: Platform) {
        id = platform.id
        name = platform.name
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Site" }
    static var defaultQuery = SiteQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct SiteQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SiteEntity] {
        identifiers.compactMap { Platform.byID($0).map(SiteEntity.init) }
    }

    // every site Runs can rest, not just the ones resting this minute — a
    // shortcut built today should still work after the block list changes
    func suggestedEntities() async throws -> [SiteEntity] {
        let custom = WebPolicy.customSites().map(Platform.custom)
        return (Platform.all + custom).map(SiteEntity.init)
    }
}

struct BreatheOpenSiteIntent: AppIntent {
    static var title: LocalizedStringResource = "Breathe to Open Site"
    static var description = IntentDescription(
        "Holds you for the breathe, then opens a resting site for its minutes. Runs never comes to the foreground, so this works from inside any browser."
    )

    // launching the app would defeat the point — this exists so the breathe can
    // happen without leaving brave
    static var openAppWhenRun = false

    @Parameter(title: "Site")
    var site: SiteEntity

    init() {}

    init(site: SiteEntity) {
        self.site = site
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let platform = Platform.byID(site.id) else {
            return .result(dialog: say("\(site.name) isn't a site runs knows."))
        }

        // another process may have moved the day on us
        let store = RunStore.shared
        store.load()
        store.rolloverIfNeeded()
        store.expireLockIfNeeded()

        if let endsAt = store.webSessionEndsAt(platform.id) {
            let left = max(1, Int(ceil(endsAt.timeIntervalSinceNow / 60)))
            return .result(dialog: say("\(platform.name) is already open. \(left) min left."))
        }

        guard store.webBlocking, isResting(platform, store) else {
            return .result(dialog: say("\(platform.name) isn't resting — open it normally."))
        }

        guard store.canStartWebSession(for: platform) else {
            return .result(dialog: say("out of runs. \(platform.name) rests until midnight."))
        }

        // the breath. there's no wall to draw out here, so the hold IS the gate
        // — the site stays blocked for every second of it.
        let seconds = store.breatheSeconds
        if seconds > 0 {
            try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
        }

        RunEngine.shared.startWebSession(for: platform)

        // startWebSession refuses if the budget went while we were breathing
        guard store.webSessionEndsAt(platform.id) != nil else {
            return .result(dialog: say("out of runs. \(platform.name) rests until midnight."))
        }
        return .result(dialog: say("\(platform.name) is open for \(store.webSessionMinutes(for: platform)) min."))
    }

    // custom sites are blocked the moment they're added, so they never appear in
    // platformOverrides — same rule WebPolicy uses to build the filter
    private func isResting(_ platform: Platform, _ store: RunStore) -> Bool {
        platform.isCustom || store.isPlatformBlocked(platform.id)
    }

    private func say(_ text: String) -> IntentDialog {
        IntentDialog(LocalizedStringResource(stringLiteral: text))
    }
}

// gives the intent a Siri phrase and a Spotlight entry with no setup. 16.4 is
// where AppShortcut gained the title/icon it needs to look like anything.
@available(iOS 16.4, *)
struct RunsAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: BreatheOpenSiteIntent(),
            phrases: [
                "Breathe to open a site in \(.applicationName)",
                "Breathe in \(.applicationName)"
            ],
            shortTitle: "Breathe to Open",
            systemImageName: "wind"
        )
    }
}
