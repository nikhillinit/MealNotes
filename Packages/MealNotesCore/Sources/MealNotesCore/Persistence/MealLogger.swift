import Foundation

public struct LoggedMeal: Sendable, Hashable {
    public let meal: MealSnapshot
    public let windowID: UUID
    public let checkInDueAt: Date
    /// True when this meal joined a recent eating window instead of starting one.
    public let joinedExistingWindow: Bool
}

/// Ties together the three things that happen when the user taps "I'm having this":
/// the meal is stored, it is placed in an eating window, and one check-in is
/// scheduled for that window.
///
/// Keeping this out of the repository means window policy stays testable without
/// a database, and out of the views means the flow has no storage knowledge.
@MainActor
public final class MealLogger {
    private let repository: any MealRepository
    private let scheduler: any CheckInScheduler

    public init(repository: any MealRepository, scheduler: any CheckInScheduler) {
        self.repository = repository
        self.scheduler = scheduler
    }

    public static func notificationID(for windowID: UUID) -> String {
        "checkin.\(windowID.uuidString)"
    }

    @discardableResult
    public func log(_ draft: MealDraft) async throws -> LoggedMeal {
        let openWindows = try repository.openWindows(asOf: draft.consumedAt)

        switch MealWindowPlanner.plan(newMealAt: draft.consumedAt, openWindows: openWindows) {
        case .createWindow(let fireDate):
            let windowID = UUID()
            let notificationID = Self.notificationID(for: windowID)
            try repository.createWindow(
                id: windowID,
                mealAt: draft.consumedAt,
                fireDate: fireDate,
                notificationID: notificationID
            )
            let meal = try repository.save(draft, windowID: windowID)
            await scheduler.schedule(
                CheckInNotificationRequest(notificationID: notificationID, windowID: windowID, fireDate: fireDate)
            )
            return LoggedMeal(
                meal: meal,
                windowID: windowID,
                checkInDueAt: fireDate,
                joinedExistingWindow: false
            )

        case .extendWindow(let windowID, let newFireDate, let notificationID):
            try repository.extendWindow(id: windowID, latestMealAt: draft.consumedAt, fireDate: newFireDate)
            let meal = try repository.save(draft, windowID: windowID)
            // Cancel then re-add so the single reminder moves to the new time
            // rather than two reminders arriving.
            await scheduler.cancel(notificationID: notificationID)
            await scheduler.schedule(
                CheckInNotificationRequest(notificationID: notificationID, windowID: windowID, fireDate: newFireDate)
            )
            return LoggedMeal(
                meal: meal,
                windowID: windowID,
                checkInDueAt: newFireDate,
                joinedExistingWindow: true
            )
        }
    }

    /// Records an answer and returns an advisory when one is warranted.
    @discardableResult
    public func recordCheckIn(
        windowID: UUID,
        severity: CheckInSeverity,
        symptoms: [SymptomTag] = [],
        urgentSymptoms: [UrgentSymptom] = [],
        at date: Date
    ) async throws -> UrgentAdvisory? {
        let response = CheckInSnapshot(
            respondedAt: date,
            severity: severity,
            symptoms: symptoms,
            urgentSymptoms: urgentSymptoms
        )
        try repository.recordCheckIn(windowID: windowID, response: response)

        if let window = try repository.window(id: windowID) {
            await scheduler.cancel(notificationID: window.notificationID)
        }

        return UrgentCarePolicy.advisory(for: urgentSymptoms)
    }
}
