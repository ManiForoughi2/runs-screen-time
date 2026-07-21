import Foundation

// single source of truth for WHICH domains are blocked right now, computed
// fresh from App Group state so the app, monitor, and shield action extension
// all agree without messaging each other.
enum WebPolicy {
    // apple's undocumented filter limit is ~50 domains, stay safely under
    static let domainCap = 45

    static var enabled: Bool {
        AppGroup.defaults.object(forKey: StoreKey.webBlocking) as? Bool ?? true
    }

    // platforms auto-detected by the shield (limitID -> platformID), pruned to
    // limits that still exist
    static func pairedPlatformIDs(excludingLimitID excluded: UUID? = nil) -> Set<String> {
        let pairs = AppGroup.defaults.dictionary(forKey: StoreKey.platformPairs) as? [String: String] ?? [:]
        let limitIDs = configuredLimitIDs()
        var ids = Set<String>()
        for (limitID, platformID) in pairs {
            guard limitIDs.contains(limitID) else { continue }
            if let excluded, limitID == excluded.uuidString { continue }
            ids.insert(platformID)
        }
        return ids
    }

    // platforms breathed open from the app right now (chrome/brave on iOS can't
    // run extensions, so web unlocks are granted in-app as timed sessions)
    static func liveSessionPlatformIDs(now: Date = Date()) -> Set<String> {
        let sessions = AppGroup.defaults.dictionary(forKey: StoreKey.webSessions) as? [String: Double] ?? [:]
        return Set(sessions.filter { $0.value > now.timeIntervalSince1970 }.keys)
    }

    // effective set = auto-detected pairs, then user overrides, minus live
    // breathe sessions, minus the app with a live run (its site runs with it)
    static func blockedDomains(excludingLimitID excluded: UUID? = nil) -> Set<String> {
        guard enabled else { return [] }

        var ids = pairedPlatformIDs()
        let overrides = AppGroup.defaults.dictionary(forKey: StoreKey.platformOverrides) as? [String: Bool] ?? [:]
        for (platformID, on) in overrides {
            if on { ids.insert(platformID) } else { ids.remove(platformID) }
        }
        ids.subtract(liveSessionPlatformIDs())
        if let excluded {
            let pairs = AppGroup.defaults.dictionary(forKey: StoreKey.platformPairs) as? [String: String] ?? [:]
            if let running = pairs[excluded.uuidString] { ids.remove(running) }
        }

        var domains = Set<String>()
        for id in ids {
            guard let platform = Platform.byID(id) else { continue }
            domains.formUnion(platform.domains)
        }
        return Set(domains.prefix(domainCap))
    }

    private static func configuredLimitIDs() -> Set<String> {
        guard let data = AppGroup.defaults.data(forKey: StoreKey.limits) else { return [] }
        struct IDOnly: Decodable { let id: UUID }
        let limits = (try? JSONDecoder().decode([IDOnly].self, from: data)) ?? []
        return Set(limits.map(\.id.uuidString))
    }
}
