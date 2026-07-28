import Foundation

/// One eating window and the single check-in that covers it.
public struct CheckInWindowSnapshot: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let windowStart: Date
    public let latestMealAt: Date
    public let scheduledFireDate: Date
    public let notificationID: String
    public let mealIDs: [UUID]
    public let response: CheckInSnapshot?

    public init(
        id: UUID,
        windowStart: Date,
        latestMealAt: Date,
        scheduledFireDate: Date,
        notificationID: String,
        mealIDs: [UUID],
        response: CheckInSnapshot? = nil
    ) {
        self.id = id
        self.windowStart = windowStart
        self.latestMealAt = latestMealAt
        self.scheduledFireDate = scheduledFireDate
        self.notificationID = notificationID
        self.mealIDs = mealIDs
        self.response = response
    }

    public var isAnswered: Bool { response != nil }

    public func isDue(at date: Date) -> Bool {
        !isAnswered && date >= scheduledFireDate
    }
}

public enum WindowPlan: Sendable, Hashable {
    /// No recent meal to join — start a new window.
    case createWindow(fireDate: Date)
    /// Fold into a recent window and move its check-in later.
    case extendWindow(id: UUID, newFireDate: Date, cancelNotificationID: String)
}

/// Decides whether a new meal joins a recent eating window or starts a new one.
///
/// Two meals close together should produce one check-in, not two — a snack after
/// dinner should not buzz the phone twice. Each meal is still recorded on its
/// own; only the check-in is shared.
public enum MealWindowPlanner {
    /// Meals within this of each other belong to the same eating window.
    public static let windowDuration: TimeInterval = 90 * 60
    /// How long after the last meal in a window to ask how things went.
    public static let checkInDelay: TimeInterval = 2 * 60 * 60

    public static func plan(newMealAt: Date, openWindows: [CheckInWindowSnapshot]) -> WindowPlan {
        // Nearest unanswered window whose most recent meal is close enough.
        // `abs` so a back-dated meal still joins the right window.
        let candidate = openWindows
            .filter { !$0.isAnswered }
            .filter { abs(newMealAt.timeIntervalSince($0.latestMealAt)) <= windowDuration }
            .max { $0.latestMealAt < $1.latestMealAt }

        guard let candidate else {
            return .createWindow(fireDate: newMealAt.addingTimeInterval(checkInDelay))
        }

        // The check-in follows the *most recent* meal in the window.
        let latest = max(candidate.latestMealAt, newMealAt)
        return .extendWindow(
            id: candidate.id,
            newFireDate: latest.addingTimeInterval(checkInDelay),
            cancelNotificationID: candidate.notificationID
        )
    }
}
