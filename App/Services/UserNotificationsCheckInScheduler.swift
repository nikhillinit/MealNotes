import Foundation
import MealNotesCore
import UserNotifications

/// Real local notifications, behind the same protocol the tests use.
///
/// Nothing here throws. If permission is refused or the system declines the
/// request, the pending check-in still exists in the database and is shown on
/// the home screen — the reminder is a convenience, not the mechanism.
struct UserNotificationsCheckInScheduler: CheckInScheduler {
    static let windowIDKey = "windowID"

    private var center: UNUserNotificationCenter { .current() }

    func currentAuthorization() async -> CheckInAuthorizationStatus {
        Self.map(await center.notificationSettings().authorizationStatus)
    }

    @discardableResult
    func requestAuthorization() async -> CheckInAuthorizationStatus {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            AppLog.notifications.error("Authorization request failed: \(error, privacy: .public)")
        }
        return await currentAuthorization()
    }

    func schedule(_ request: CheckInNotificationRequest) async {
        guard request.fireDate > Date() else {
            AppLog.notifications.info("Skipped a check-in reminder that was already due.")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = [Self.windowIDKey: request.windowID.uuidString]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: request.fireDate
        )
        let notification = UNNotificationRequest(
            identifier: request.notificationID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )

        do {
            try await center.add(notification)
        } catch {
            AppLog.notifications.error("Could not schedule a reminder: \(error, privacy: .public)")
        }
    }

    func cancel(notificationID: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
    }

    func pendingNotificationIDs() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    private static func map(_ status: UNAuthorizationStatus) -> CheckInAuthorizationStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .ephemeral: .authorized
        case .provisional: .provisional
        @unknown default: .notDetermined
        }
    }
}
