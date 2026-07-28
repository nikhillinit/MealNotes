import Foundation
import Testing
@testable import MealNotesCore

@Suite("Eating windows")
struct MealWindowPlannerTests {
    private func window(
        latestMealAt: Date,
        answered: Bool = false,
        id: UUID = UUID()
    ) -> CheckInWindowSnapshot {
        CheckInWindowSnapshot(
            id: id,
            windowStart: latestMealAt,
            latestMealAt: latestMealAt,
            scheduledFireDate: latestMealAt.addingTimeInterval(MealWindowPlanner.checkInDelay),
            notificationID: "checkin.\(id.uuidString)",
            mealIDs: [],
            response: answered
                ? CheckInSnapshot(respondedAt: latestMealAt, severity: .fine)
                : nil
        )
    }

    @Test("The first meal of the day starts a window, checked two hours later")
    func firstMealCreatesWindow() {
        let plan = MealWindowPlanner.plan(newMealAt: TestDates.at(12), openWindows: [])

        #expect(plan == .createWindow(fireDate: TestDates.at(14)))
    }

    @Test("A meal within ninety minutes joins the window and moves the check-in")
    func coalescesWithinWindow() throws {
        let existing = window(latestMealAt: TestDates.at(12))
        let plan = MealWindowPlanner.plan(newMealAt: TestDates.at(13, 15), openWindows: [existing])

        #expect(plan == .extendWindow(
            id: existing.id,
            newFireDate: TestDates.at(15, 15),
            cancelNotificationID: existing.notificationID
        ))
    }

    @Test("Exactly ninety minutes still counts as the same window")
    func boundaryIsInclusive() {
        let existing = window(latestMealAt: TestDates.at(12))
        let atBoundary = TestDates.at(12).addingTimeInterval(MealWindowPlanner.windowDuration)

        guard case .extendWindow = MealWindowPlanner.plan(newMealAt: atBoundary, openWindows: [existing]) else {
            Issue.record("a meal exactly at the boundary should join the window")
            return
        }
    }

    @Test("A meal more than ninety minutes later starts a new window")
    func separateWindows() {
        let existing = window(latestMealAt: TestDates.at(12))
        let plan = MealWindowPlanner.plan(newMealAt: TestDates.at(13, 31), openWindows: [existing])

        #expect(plan == .createWindow(fireDate: TestDates.at(15, 31)))
    }

    @Test("An answered window does not absorb a new meal")
    func answeredWindowIsClosed() {
        let existing = window(latestMealAt: TestDates.at(12), answered: true)
        let plan = MealWindowPlanner.plan(newMealAt: TestDates.at(12, 30), openWindows: [existing])

        #expect(plan == .createWindow(fireDate: TestDates.at(14, 30)))
    }

    @Test("With several open windows, the most recent one wins")
    func picksMostRecentWindow() throws {
        let older = window(latestMealAt: TestDates.at(11, 30))
        let newer = window(latestMealAt: TestDates.at(12, 30))

        let plan = MealWindowPlanner.plan(newMealAt: TestDates.at(12, 45), openWindows: [older, newer])

        guard case .extendWindow(let id, let fireDate, _) = plan else {
            Issue.record("expected the newer window to be extended")
            return
        }
        #expect(id == newer.id)
        #expect(fireDate == TestDates.at(14, 45))
    }

    @Test("A back-dated meal joins its window without pulling the check-in earlier")
    func backdatedMealKeepsLaterFireDate() throws {
        let existing = window(latestMealAt: TestDates.at(12, 30))
        let plan = MealWindowPlanner.plan(newMealAt: TestDates.at(12, 0), openWindows: [existing])

        guard case .extendWindow(_, let fireDate, _) = plan else {
            Issue.record("expected the window to be extended")
            return
        }
        #expect(fireDate == TestDates.at(14, 30))
    }
}

@Suite("Logging a meal schedules one check-in")
@MainActor
struct MealLoggerTests {
    private func makeLogger() throws -> (MealLogger, SwiftDataMealRepository, InMemoryCheckInScheduler) {
        let repository = SwiftDataMealRepository(container: try MealNotesSchema.inMemoryContainer())
        let scheduler = InMemoryCheckInScheduler()
        return (MealLogger(repository: repository, scheduler: scheduler), repository, scheduler)
    }

    @Test("One meal schedules one reminder two hours later")
    func singleMeal() async throws {
        let (logger, _, scheduler) = try makeLogger()

        let logged = try await logger.log(.stub(at: TestDates.at(12), name: "Tea"))

        #expect(logged.checkInDueAt == TestDates.at(14))
        #expect(logged.joinedExistingWindow == false)

        let scheduled = await scheduler.scheduled
        #expect(scheduled.count == 1)
        #expect(scheduled[0].fireDate == TestDates.at(14))
        #expect(scheduled[0].body == "How are you feeling after your meal?")
    }

    @Test("Two meals close together produce one reminder, but two records")
    func coalescedNotification() async throws {
        let (logger, repository, scheduler) = try makeLogger()

        let first = try await logger.log(.stub(at: TestDates.at(12), name: "Tea"))
        let second = try await logger.log(.stub(at: TestDates.at(12, 30), name: "Toast"))

        #expect(second.joinedExistingWindow)
        #expect(second.windowID == first.windowID)

        // One reminder, moved to two hours after the later meal.
        let scheduled = await scheduler.scheduled
        #expect(scheduled.count == 1)
        #expect(scheduled[0].fireDate == TestDates.at(14, 30))
        #expect(await scheduler.cancelledIDs == [MealLogger.notificationID(for: first.windowID)])

        // Both meals are still recorded separately.
        let meals = try repository.allMeals()
        #expect(meals.count == 2)
        #expect(Set(meals.map(\.displayName)) == ["Tea", "Toast"])
        #expect(Set(meals.compactMap(\.windowID)).count == 1)

        let window = try #require(try repository.window(id: first.windowID))
        #expect(window.mealIDs.count == 2)
        #expect(window.windowStart == TestDates.at(12))
        #expect(window.latestMealAt == TestDates.at(12, 30))
    }

    @Test("Meals far apart produce two reminders")
    func separateWindowsScheduleSeparately() async throws {
        let (logger, _, scheduler) = try makeLogger()

        let breakfast = try await logger.log(.stub(at: TestDates.at(8), name: "Toast"))
        let lunch = try await logger.log(.stub(at: TestDates.at(13), name: "Soup"))

        #expect(lunch.windowID != breakfast.windowID)
        let scheduled = await scheduler.scheduled.sorted { $0.fireDate < $1.fireDate }
        #expect(scheduled.map(\.fireDate) == [TestDates.at(10), TestDates.at(15)])
    }

    @Test("Answering a check-in cancels its reminder and closes the window")
    func answeringClosesWindow() async throws {
        let (logger, repository, scheduler) = try makeLogger()
        let logged = try await logger.log(.stub(at: TestDates.at(12), name: "Tea"))

        let advisory = try await logger.recordCheckIn(
            windowID: logged.windowID,
            severity: .mild,
            symptoms: [.heartburn],
            at: TestDates.at(14, 5)
        )

        #expect(advisory == nil)
        #expect(await scheduler.scheduled.isEmpty)

        let meal = try #require(repository.allMeals().first)
        #expect(meal.checkIn?.severity == .mild)
        #expect(meal.checkIn?.symptoms == [.heartburn])

        // A later meal starts a fresh window rather than reopening the answered one.
        let next = try await logger.log(.stub(at: TestDates.at(12, 40), name: "Biscuit"))
        #expect(next.windowID != logged.windowID)
    }

    @Test("Recording an urgent symptom returns an advisory")
    func urgentSymptomAdvisory() async throws {
        let (logger, _, _) = try makeLogger()
        let logged = try await logger.log(.stub(at: TestDates.at(12), name: "Dinner"))

        let advisory = try await logger.recordCheckIn(
            windowID: logged.windowID,
            severity: .severe,
            symptoms: [.stomachPain],
            urgentSymptoms: [.chestPain],
            at: TestDates.at(14, 5)
        )

        #expect(advisory?.symptoms == [.chestPain])
    }

    @Test("A pending check-in is available in the app even with notifications denied")
    func pendingCheckInWithoutNotifications() async throws {
        let repository = SwiftDataMealRepository(container: try MealNotesSchema.inMemoryContainer())
        let scheduler = InMemoryCheckInScheduler(authorization: .denied)
        let logger = MealLogger(repository: repository, scheduler: scheduler)

        let logged = try await logger.log(.stub(at: TestDates.at(12), name: "Tea"))

        #expect(try repository.dueWindows(asOf: TestDates.at(13)).isEmpty)
        let due = try repository.dueWindows(asOf: TestDates.at(14, 1))
        #expect(due.map(\.id) == [logged.windowID])
    }
}
