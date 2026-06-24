import Foundation
import ManagedSettings

// read-only mirror of the App Group state, extension cant import the Runs app target
struct ShieldStore {
    // must match AppGroup.id / StoreKey.* in the main app
    private static let groupID = "group.com.manif.runs"
    private static let kLimits = "runs.limits.v1"
    private static let kDayState = "runs.dayState.v1"
    private static let kRunMode = "runs.runMode.v1"
    private static let kSharedRuns = "runs.sharedRuns.v1"
    private static let kSharedUsed = "runs.sharedUsed.v1"

    private static let kActiveRun = "runs.activeRun.v1"

    private let defaults = UserDefaults(suiteName: groupID)
    private let limits: [Limit]
    private let runsUsedByID: [String: Int]
    private let runMode: String
    private let sharedRuns: Int
    private let sharedUsed: Int
    private let activeRunLimitID: String?
    private let activeRunEndsAt: Date?

    init() {
        let d = UserDefaults(suiteName: Self.groupID)
        limits = Self.decode([Limit].self, Self.kLimits, d) ?? []
        runsUsedByID = (Self.decode(DayState.self, Self.kDayState, d))?.runsUsed ?? [:]
        runMode = d?.string(forKey: Self.kRunMode) ?? "perApp"
        sharedRuns = d?.object(forKey: Self.kSharedRuns) as? Int ?? 4
        sharedUsed = d?.integer(forKey: Self.kSharedUsed) ?? 0
        let run = Self.decode(ActiveRunDTO.self, Self.kActiveRun, d)
        activeRunLimitID = run?.limitID.uuidString
        activeRunEndsAt = run?.endsAt
    }

    func limit(for token: ApplicationToken) -> Limit? {
        limits.first { $0.token == token }
    }

    // true only if there's a persisted run for THIS limit whose wall-clock end is
    // still in the future. if iOS draws the shield for an app whose run already
    // expired (stale state), this returns false so we show the real block, never
    // a "your run is active" pass.
    func hasLiveRun(for limit: Limit) -> Bool {
        guard let id = activeRunLimitID, id == limit.id,
              let endsAt = activeRunEndsAt else { return false }
        return Date() < endsAt
    }

    private struct ActiveRunDTO: Decodable {
        let limitID: UUID
        let endsAt: Date
    }

    // NOTE: fresh read per shield show, reflects rollover only after app/monitor
    // rewrites dayState, same eventual-consistency the app relies on
    func runsLeft(for limit: Limit) -> Int {
        switch runMode {
        case "shared":
            return max(0, sharedRuns - sharedUsed)
        default: // perApp
            let used = runsUsedByID[limit.id] ?? 0
            return max(0, limit.runsPerDay - used)
        }
    }

    struct Limit: Decodable {
        let id: String
        let token: ApplicationToken
        let label: String
        let runsPerDay: Int

        // decode UUID id as its string form to key into DayState.runsUsed
        enum CodingKeys: String, CodingKey { case id, token, label, runsPerDay }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id).uuidString
            token = try c.decode(ApplicationToken.self, forKey: .token)
            label = try c.decode(String.self, forKey: .label)
            runsPerDay = try c.decode(Int.self, forKey: .runsPerDay)
        }
    }

    private struct DayState: Decodable {
        let runsUsed: [String: Int]

        // source is [UUID: Int]; JSONEncoder writes non-String-keyed dicts as a
        // flat [key, value, ...] array, reconstruct from that
        enum CodingKeys: String, CodingKey { case runsUsed }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            var flat = try c.nestedUnkeyedContainer(forKey: .runsUsed)
            var map: [String: Int] = [:]
            while !flat.isAtEnd {
                let uuid = try flat.decode(UUID.self)
                let count = try flat.decode(Int.self)
                map[uuid.uuidString] = count
            }
            runsUsed = map
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ key: String, _ d: UserDefaults?) -> T? {
        guard let data = d?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
