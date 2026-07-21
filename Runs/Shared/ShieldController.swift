import Foundation
import ManagedSettings
import FamilyControls

// every configured app is shielded except the one with an active run
struct ShieldController {
    // named store so the monitor extension addresses the exact same shield
    static let storeName = ManagedSettingsStore.Name("runs.main")
    private let store = ManagedSettingsStore(named: storeName)

    func applyShield(allTokens: Set<ApplicationToken>,
                     except open: ApplicationToken? = nil,
                     unshieldAll: Bool = false) {
        if unshieldAll {
            store.shield.applications = nil
            return
        }
        var blocked = allTokens
        if let open { blocked.remove(open) }

        if blocked.isEmpty {
            store.shield.applications = nil
        } else {
            store.shield.applications = blocked
        }
    }

    // safari-level block for the catalog-matched sites (instagram.com etc).
    // apple renders its own "restricted" page for these, not our shield
    func applyWebFilter(_ domains: Set<String>) {
        if domains.isEmpty {
            store.webContent.blockedByFilter = nil
        } else {
            store.webContent.blockedByFilter = .specific(Set(domains.map { WebDomain(domain: $0) }))
        }
    }

    // sites hand-picked in the picker get the full custom shield in safari
    func applyWebShield(_ tokens: Set<WebDomainToken>?) {
        if let tokens, !tokens.isEmpty {
            store.shield.webDomains = tokens
        } else {
            store.shield.webDomains = nil
        }
    }

    func clearAll() {
        store.shield.applications = nil
        store.shield.webDomains = nil
        store.webContent.blockedByFilter = nil
        store.clearAllSettings()
    }
}
