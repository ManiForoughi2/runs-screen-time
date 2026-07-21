import ManagedSettings
import ManagedSettingsUI
import UIKit

enum ShieldState {
    case outOfRuns(label: String?)
    case fullBlock(label: String?)
    case blocked(label: String?)
    case webBlocked(domain: String?)
    // breathe-to-open: ready shows the invitation, breathing shows the pause.
    // the shield can't animate or tick, so the flow is tap-driven: each tap on
    // I'M READY re-renders this state with the remaining seconds until the
    // action extension finally lets the run start.
    case breatheReady(label: String?)
    case breathing(label: String?, remaining: Int)

    // shield primitives are UIKit-only, no FairfaxHD or SwiftUI; match theme via color + wordmark
    private static let bg = UIColor.black
    private static let fg = UIColor.white
    private static let dim = UIColor(white: 1.0, alpha: 0.5)

    func configuration() -> ShieldConfiguration {
        let icon = UIImage(named: "ShieldGlyph")

        switch self {
        case .outOfRuns(let label):
            return Self.make(
                icon: icon,
                title: Self.wordmark(label),
                subtitle: "out of runs for today.\nresets at midnight.",
                primary: "OK"
            )

        case .fullBlock(let label):
            return Self.make(
                icon: icon,
                title: Self.wordmark(label),
                subtitle: "full block is on.\nemergency only.",
                primary: "OK"
            )

        case .blocked(let label):
            return Self.make(
                icon: icon,
                title: Self.wordmark(label),
                subtitle: "this app is resting.\nopen Runs to start a run.",
                // iOS wont let the extension launch Runs, so the button only
                // dismisses. labelled DISMISS so it doesnt promise a launch it
                // cant deliver; the subtitle is the real call to action.
                primary: "DISMISS"
            )

        case .webBlocked(let domain):
            return Self.make(
                icon: icon,
                title: Self.wordmark(domain),
                subtitle: "this site is resting.",
                primary: "DISMISS"
            )

        case .breatheReady(let label):
            return Self.make(
                icon: icon,
                title: Self.wordmark(label),
                subtitle: "this app is resting.\none breath starts a run.",
                primary: "TAKE A BREATH",
                secondary: "CLOSE"
            )

        case .breathing(let label, let remaining):
            return Self.make(
                icon: icon,
                title: Self.wordmark(label),
                subtitle: remaining > 0
                    ? "breathe in…\nbreathe out…\n\(remaining)s"
                    : "breathe in…\nbreathe out…",
                primary: "I'M READY",
                secondary: "CLOSE"
            )
        }
    }

    private static func make(icon: UIImage?, title: String, subtitle: String,
                             primary: String, secondary: String? = nil) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .dark,
            backgroundColor: bg,
            icon: icon,
            title: ShieldConfiguration.Label(text: title, color: fg),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: dim),
            primaryButtonLabel: ShieldConfiguration.Label(text: primary, color: bg),
            primaryButtonBackgroundColor: fg,
            secondaryButtonLabel: secondary.map { ShieldConfiguration.Label(text: $0, color: dim) }
        )
    }

    private static func wordmark(_ label: String?) -> String {
        if let label, !label.isEmpty {
            return "RUNS\n\(label.uppercased())"
        }
        return "RUNS"
    }

    // breathe sessions older than this are abandoned, start fresh
    static let sessionTimeout: TimeInterval = 180

    static func resolve(for token: ApplicationToken?) -> ShieldState {
        let store = ShieldStore()
        guard let token, let limit = store.limit(for: token) else {
            return .blocked(label: nil)
        }
        // stale shield over the app whose own run is live: show plain block,
        // never a breathe invite that would double-spend a run
        if store.hasLiveRun(for: limit) {
            return .blocked(label: limit.label)
        }
        if store.fullBlock {
            return .fullBlock(label: limit.label)
        }
        // solo breathe has no budget: "out of runs" can never happen
        if !store.breatheSolo && store.runsLeft(for: limit) <= 0 {
            return .outOfRuns(label: limit.label)
        }
        // another app's run is live: only one run at a time
        if store.anyLiveRun {
            return .blocked(label: limit.label)
        }
        guard store.breatheSeconds > 0 else {
            return .blocked(label: limit.label)
        }
        if let session = store.breatheSession,
           session.limitID.uuidString == limit.id,
           Date().timeIntervalSince(session.startedAt) < Self.sessionTimeout {
            let elapsed = Date().timeIntervalSince(session.startedAt)
            let remaining = max(0, Int((Double(store.breatheSeconds) - elapsed).rounded(.up)))
            return .breathing(label: limit.label, remaining: remaining)
        }
        return .breatheReady(label: limit.label)
    }
}
