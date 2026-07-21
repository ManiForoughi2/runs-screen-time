import Foundation
import ManagedSettings
import FamilyControls
import SwiftUI

enum ThemeMode: String, Codable, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return "SYSTEM"
        case .light: return "LIGHT"
        case .dark: return "DARK"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum RunMode: String, Codable, CaseIterable {
    case perApp   // each app has its own runs/day
    case shared   // one pool shared across all apps
}

// presets are by use-case since Apple wont let us name the picked apps
struct RunPreset: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let hint: String       // example apps
    let minutes: Int
    let runs: Int

    static let all: [RunPreset] = [
        RunPreset(name: "SCROLL", hint: "x, instagram, tiktok", minutes: 3, runs: 4),
        RunPreset(name: "WATCH", hint: "youtube, netflix", minutes: 15, runs: 2),
        RunPreset(name: "PEEK", hint: "news, reddit", minutes: 5, runs: 3),
        RunPreset(name: "STRICT", hint: "one quick hit", minutes: 2, runs: 2)
    ]
}

// how long settings cant be loosened
enum LockDuration: String, Codable, CaseIterable, Identifiable {
    case off, day, week, month, forever

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "OFF"
        case .day: return "1D"
        case .week: return "7D"
        case .month: return "30D"
        case .forever: return "∞"
        }
    }

    // nil = off, .infinity = forever
    var seconds: TimeInterval? {
        switch self {
        case .off: return nil
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        case .forever: return .infinity
        }
    }
}

struct LimitConfig: Codable, Identifiable, Hashable {
    var id: UUID
    var token: ApplicationToken
    var label: String          // user-set name, Apple masks the real one
    var minutesPerRun: Int
    var runsPerDay: Int

    init(id: UUID = UUID(), token: ApplicationToken, label: String, minutesPerRun: Int, runsPerDay: Int) {
        self.id = id
        self.token = token
        self.label = label
        self.minutesPerRun = minutesPerRun
        self.runsPerDay = runsPerDay
    }
}

struct DayState: Codable {
    var day: String                       // yyyy-MM-dd, used to detect rollover
    var runsUsed: [UUID: Int]             // limit.id -> runs spent today

    static func today(calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static func fresh() -> DayState { DayState(day: today(), runsUsed: [:]) }
}

// only one app open at a time
struct ActiveRun: Codable, Equatable {
    var limitID: UUID
    var label: String
    var startedAt: Date
    var endsAt: Date
    var minutesPerRun: Int
    // an emergency run (full-block escape hatch) unshields EVERY app for its
    // duration instead of all-except-one, and doesn't spend a normal run.
    var isEmergency: Bool = false
}

// full-block emergency allowance: N uses per rolling window. we store the
// timestamps of spent emergencies and count only those still inside the window.
enum Emergency {
    static let total = 3
    static let minutes = 3
    static let windowSeconds: TimeInterval = 7 * 86_400
}
