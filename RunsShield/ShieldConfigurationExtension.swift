import ManagedSettings
import ManagedSettingsUI
import UIKit

// custom block screen iOS shows for a shielded app. own process, cant import
// RunStore so it decodes the App Group state directly
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        recordPairing(application)
        return ShieldState.resolve(for: application.token).configuration()
    }

    // we dont shield categories but the API requires this override
    override func configuration(shielding application: Application,
                                in category: ActivityCategory) -> ShieldConfiguration {
        recordPairing(application)
        return ShieldState.resolve(for: application.token).configuration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        ShieldState.webBlocked(domain: webDomain.domain).configuration()
    }

    override func configuration(shielding webDomain: WebDomain,
                                in category: ActivityCategory) -> ShieldConfiguration {
        ShieldState.webBlocked(domain: webDomain.domain).configuration()
    }

    // the smart app<->website link. tokens are opaque to the main app, but HERE
    // apple hands us the shielded app's identity — so the first time a shield
    // renders for e.g. Instagram we durably record limitID -> "instagram", and
    // every web-filter apply point picks up instagram.com from then on.
    private func recordPairing(_ application: Application) {
        guard let platform = Platform.match(
            bundleID: application.bundleIdentifier,
            name: application.localizedDisplayName
        ) else { return }
        guard let token = application.token,
              let limit = ShieldStore().limit(for: token)
        else { return }

        let defaults = AppGroup.defaults
        var pairs = defaults.dictionary(forKey: StoreKey.platformPairs) as? [String: String] ?? [:]
        guard pairs[limit.id] != platform.id else { return }
        pairs[limit.id] = platform.id
        defaults.set(pairs, forKey: StoreKey.platformPairs)
    }
}
