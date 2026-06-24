import Foundation
import UserNotifications

// the wall-clock "alarm" for a run ending. local notifications have no 15-min
// floor, so this fires on time even for a 2-min run. it cant re-shield by itself,
// but it's time-sensitive (breaks through Focus/silent) and tapping it deep-links
// into Runs, which reconciles + re-locks immediately.
enum RunNotifier {
    private static let endID = "runs.run-ended"
    static let deepLink = "screenrun://run-ended"

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }

    static func scheduleRunEnd(label: String, at date: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [endID])

        let interval = date.timeIntervalSinceNow
        // already past (or basically now), nothing to schedule
        guard interval > 0.5 else { return }

        let content = UNMutableNotificationContent()
        let name = label.isEmpty ? "Your run" : label
        content.title = "\(name) is up"
        content.body = "Time's up. Tap to lock it back."
        content.sound = .default
        // break through silent mode / Focus so the run actually ends loudly
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: interval,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: endID,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    static func cancelRunEnd() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [endID])
        center.removeDeliveredNotifications(withIdentifiers: [endID])
    }
}
