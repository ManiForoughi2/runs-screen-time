import Foundation
import ManagedSettings

// read/write mirror of the App Group state. the action extension is its own
// process and cant import the app target, so like the shield's ShieldStore it
// decodes group defaults directly — but this one also WRITES: breathe sessions,
// spent counters, and the active run itself (breathe-to-open starts runs here).
final class ActionStore {
    private let defaults = AppGroup.defaults

    struct Limit: Decodable {
        let id: UUID
        let token: ApplicationToken
        let label: String
        let minutesPerRun: Int
        let runsPerDay: Int
    }

    struct BreatheSession: Codable {
        let limitID: UUID
        let startedAt: Date
    }

    // field-for-field match of the app's ActiveRun, default coding both sides
    struct ActiveRunDTO: Codable {
        var limitID: UUID
        var label: String
        var startedAt: Date
        var endsAt: Date
        var minutesPerRun: Int
        var isEmergency: Bool
    }

    let limits: [Limit]
    let fullBlock: Bool
    let breatheSeconds: Int
    let breatheSolo: Bool
    let breatheSession: BreatheSession?

    private let dayState: DayStateDTO
    private let runMode: String
    private let sharedRuns: Int
    private let sharedUsed: Int
    private let activeRunEndsAt: Date?
    private let activeRunLimitID: UUID?

    init() {
        limits = Self.decode([Limit].self, StoreKey.limits) ?? []
        dayState = Self.decode(DayStateDTO.self, StoreKey.dayState) ?? DayStateDTO(day: Self.today(), runsUsed: [:])
        // missing key means the user never changed modes; the app's default is shared
        runMode = AppGroup.defaults.string(forKey: StoreKey.runMode) ?? "shared"
        sharedRuns = AppGroup.defaults.object(forKey: StoreKey.sharedRuns) as? Int ?? 4
        sharedUsed = AppGroup.defaults.integer(forKey: StoreKey.sharedUsed)
        fullBlock = AppGroup.defaults.bool(forKey: StoreKey.fullBlock)
        breatheSeconds = AppGroup.defaults.object(forKey: StoreKey.breatheSeconds) as? Int ?? 5
        breatheSolo = AppGroup.defaults.bool(forKey: StoreKey.breatheSolo)
        breatheSession = Self.decode(BreatheSession.self, StoreKey.breatheSession)
        let run = Self.decode(ActiveRunDTO.self, StoreKey.activeRun)
        activeRunEndsAt = run?.endsAt
        activeRunLimitID = run?.limitID
    }

    func limit(for token: ApplicationToken) -> Limit? {
        limits.first { $0.token == token }
    }

    var anyLiveRun: Bool {
        guard let activeRunEndsAt else { return false }
        return Date() < activeRunEndsAt
    }

    func hasLiveRun(for limit: Limit) -> Bool {
        guard let activeRunLimitID, let activeRunEndsAt else { return false }
        return activeRunLimitID == limit.id && Date() < activeRunEndsAt
    }

    // counts as of TODAY: a tap after midnight but before the daily reset landed
    // must see a fresh day, not yesterday's spent runs
    private var isToday: Bool { dayState.day == Self.today() }

    func runsLeft(for limit: Limit) -> Int {
        if fullBlock { return 0 }
        let dayUsed = isToday ? (dayState.runsUsed[limit.id.uuidString] ?? 0) : 0
        let poolUsed = isToday ? sharedUsed : 0
        switch runMode {
        case "shared": return max(0, sharedRuns - poolUsed)
        default: return max(0, limit.runsPerDay - dayUsed)
        }
    }

    // MARK: writes

    func writeBreatheSession(for limit: Limit) {
        encode(BreatheSession(limitID: limit.id, startedAt: Date()), StoreKey.breatheSession)
    }

    func clearBreatheSession() {
        defaults.removeObject(forKey: StoreKey.breatheSession)
    }

    // spend a run and persist the active run, mirroring RunStore.beginRun
    func beginRun(for limit: Limit) -> ActiveRunDTO {
        let today = Self.today()
        var day = isToday ? dayState : DayStateDTO(day: today, runsUsed: [:])
        var poolUsed = isToday ? sharedUsed : 0

        // solo breathe has no budget, nothing to spend
        if !breatheSolo {
            switch runMode {
            case "shared":
                poolUsed += 1
            default:
                day.runsUsed[limit.id.uuidString] = (day.runsUsed[limit.id.uuidString] ?? 0) + 1
            }
        }
        encode(day, StoreKey.dayState)
        defaults.set(poolUsed, forKey: StoreKey.sharedUsed)

        let now = Date()
        let run = ActiveRunDTO(
            limitID: limit.id,
            label: limit.label,
            startedAt: now,
            endsAt: now.addingTimeInterval(TimeInterval(limit.minutesPerRun * 60)),
            minutesPerRun: limit.minutesPerRun,
            isEmergency: false
        )
        encode(run, StoreKey.activeRun)
        return run
    }

    // MARK: day state coding

    // source of truth is the app's [UUID: Int], which JSONEncoder writes as a
    // flat [key, value, ...] array; mirror that exactly in both directions
    struct DayStateDTO: Codable {
        var day: String
        var runsUsed: [String: Int]

        enum CodingKeys: String, CodingKey { case day, runsUsed }

        init(day: String, runsUsed: [String: Int]) {
            self.day = day
            self.runsUsed = runsUsed
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            day = try c.decode(String.self, forKey: .day)
            var flat = try c.nestedUnkeyedContainer(forKey: .runsUsed)
            var map: [String: Int] = [:]
            while !flat.isAtEnd {
                let uuid = try flat.decode(UUID.self)
                let count = try flat.decode(Int.self)
                map[uuid.uuidString] = count
            }
            runsUsed = map
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(day, forKey: .day)
            var flat = c.nestedUnkeyedContainer(forKey: .runsUsed)
            for (key, count) in runsUsed {
                guard let uuid = UUID(uuidString: key) else { continue }
                try flat.encode(uuid)
                try flat.encode(count)
            }
        }
    }

    private static func today() -> String {
        let f = DateFormatter()
        f.calendar = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = AppGroup.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}
