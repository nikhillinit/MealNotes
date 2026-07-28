import Foundation
import SwiftData
import Testing
@testable import MealNotesCore

@Suite("SwiftData persistence")
@MainActor
struct PersistenceTests {
    private func repository() throws -> SwiftDataMealRepository {
        SwiftDataMealRepository(container: try MealNotesSchema.inMemoryContainer())
    }

    @Test("A saved meal keeps its facts, rules, provenance and time")
    func roundTrip() throws {
        let repository = try repository()
        let facts: [FoodFact] = [
            .confirmed(.caffeine, isPresent: true, detail: "black tea"),
            FoodFact(category: .tomato, isPresent: false, source: .labelText, confidence: 0.8)
        ]
        let draft = MealDraft(
            consumedAt: TestDates.at(9),
            displayName: "Black tea",
            facts: facts,
            shownRuleIDs: ["rule.caffeine.v1"],
            provenance: RecognitionProvenance(
                fixtureID: "caffeinatedTea",
                proposedName: "Black tea",
                overallConfidence: 0.78,
                repairAttempted: false,
                limitations: ["A photo cannot show whether a tea is decaffeinated."]
            )
        )

        let saved = try repository.save(draft, windowID: nil)
        let fetched = try #require(try repository.meal(id: saved.id))

        #expect(fetched.displayName == "Black tea")
        #expect(fetched.consumedAt == TestDates.at(9))
        #expect(Set(fetched.facts) == Set(facts))
        #expect(fetched.shownRuleIDs == ["rule.caffeine.v1"])
        #expect(fetched.provenance.proposedName == "Black tea")
        #expect(fetched.provenance.limitations.count == 1)
        #expect(fetched.retainedPhoto == false)
    }

    @Test("Photos are only kept when one was explicitly retained")
    func photoRetentionIsOptIn() throws {
        let repository = try repository()

        let discarded = try repository.save(.stub(at: TestDates.at(9), name: "Tea"), windowID: nil)
        #expect(discarded.retainedPhoto == false)

        var kept = MealDraft.stub(at: TestDates.at(10), name: "Cake")
        kept.retainedPhotoData = Data(repeating: 0xAB, count: 64)
        #expect(try repository.save(kept, windowID: nil).retainedPhoto)
    }

    @Test("A correction updates the meal and records what changed")
    func correctionsAreRecorded() throws {
        let repository = try repository()
        let saved = try repository.save(
            .stub(at: TestDates.at(9), name: "Tea", facts: [.confirmed(.caffeine, isPresent: true)]),
            windowID: nil
        )

        let corrected = try repository.applyCorrection(
            mealID: saved.id,
            newDisplayName: "Peppermint tea",
            newFacts: [.confirmed(.mint, isPresent: true)],
            at: TestDates.at(9, 5)
        )

        #expect(corrected.displayName == "Peppermint tea")
        #expect(corrected.facts.map(\.category) == [.mint])
        #expect(corrected.corrections.count == 2)

        let nameChange = try #require(corrected.corrections.first { $0.field == .name })
        #expect(nameChange.previousValue == "Tea")
        #expect(nameChange.newValue == "Peppermint tea")

        let ingredientChange = try #require(corrected.corrections.first { $0.field == .ingredients })
        #expect(ingredientChange.previousValue == "Caffeine")
        #expect(ingredientChange.newValue == "Mint")
    }

    @Test("An unchanged correction records nothing")
    func noOpCorrection() throws {
        let repository = try repository()
        let saved = try repository.save(.stub(at: TestDates.at(9), name: "Tea"), windowID: nil)

        let result = try repository.applyCorrection(
            mealID: saved.id,
            newDisplayName: "Tea",
            newFacts: nil,
            at: TestDates.at(9, 5)
        )
        #expect(result.corrections.isEmpty)
    }

    @Test("Correcting a meal that does not exist reports it")
    func missingMeal() throws {
        let repository = try repository()
        #expect(throws: RepositoryError.self) {
            try repository.applyCorrection(
                mealID: UUID(), newDisplayName: "x", newFacts: nil, at: TestDates.at(9)
            )
        }
    }

    @Test("Meals come back newest first, and can be limited")
    func ordering() throws {
        let repository = try repository()
        for hour in [9, 13, 19] {
            try repository.save(.stub(at: TestDates.at(hour), name: "Meal \(hour)"), windowID: nil)
        }

        #expect(try repository.allMeals().map(\.displayName) == ["Meal 19", "Meal 13", "Meal 9"])
        #expect(try repository.recentMeals(limit: 2).map(\.displayName) == ["Meal 19", "Meal 13"])
    }

    @Test("A check-in answer is joined onto every meal in its window")
    func checkInJoinsWindow() throws {
        let repository = try repository()
        let windowID = UUID()
        try repository.createWindow(
            id: windowID, mealAt: TestDates.at(12), fireDate: TestDates.at(14), notificationID: "n"
        )
        try repository.save(.stub(at: TestDates.at(12), name: "Soup"), windowID: windowID)
        try repository.save(.stub(at: TestDates.at(12, 20), name: "Bread"), windowID: windowID)

        try repository.recordCheckIn(
            windowID: windowID,
            response: CheckInSnapshot(respondedAt: TestDates.at(14, 5), severity: .moderate, symptoms: [.bloating])
        )

        let meals = try repository.allMeals()
        #expect(meals.count == 2)
        #expect(meals.allSatisfy { $0.checkIn?.severity == .moderate })
        #expect(meals.allSatisfy { $0.checkIn?.symptoms == [.bloating] })
    }

    @Test("Answering an unknown window reports it")
    func missingWindow() throws {
        let repository = try repository()
        #expect(throws: RepositoryError.self) {
            try repository.recordCheckIn(
                windowID: UUID(),
                response: CheckInSnapshot(respondedAt: TestDates.at(14), severity: .fine)
            )
        }
    }

    @Test("Deleting everything leaves nothing behind")
    func deleteAll() throws {
        let repository = try repository()
        let windowID = UUID()
        try repository.createWindow(
            id: windowID, mealAt: TestDates.at(12), fireDate: TestDates.at(14), notificationID: "n"
        )
        try repository.save(.stub(at: TestDates.at(12)), windowID: windowID)

        try repository.deleteAllData()

        #expect(try repository.allMeals().isEmpty)
        #expect(try repository.openWindows(asOf: TestDates.at(12)).isEmpty)
    }

    // MARK: - Relaunch

    @Test("Meals and check-ins survive the app being closed and reopened")
    func survivesRelaunch() async throws {
        let directory = URL.temporaryDirectory
            .appending(path: "MealNotesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appending(path: "MealNotes.store")
        let mealID = UUID()

        // First launch: log a meal and answer its check-in.
        try await withStore(at: storeURL) { repository in
            let logger = MealLogger(repository: repository, scheduler: InMemoryCheckInScheduler())
            var draft = MealDraft.stub(
                at: TestDates.at(19),
                name: "Pasta in tomato sauce",
                facts: [.confirmed(.tomato, isPresent: true)],
                shownRuleIDs: ["rule.acidicFoods.v1"]
            )
            draft.id = mealID
            let logged = try await logger.log(draft)
            _ = try await logger.recordCheckIn(
                windowID: logged.windowID, severity: .mild, symptoms: [.heartburn], at: TestDates.at(21)
            )
        }

        // Second launch: a brand new container over the same file.
        try await withStore(at: storeURL) { repository in
            let meals = try repository.allMeals()
            #expect(meals.count == 1)

            let meal = try #require(meals.first)
            #expect(meal.id == mealID)
            #expect(meal.displayName == "Pasta in tomato sauce")
            #expect(meal.facts.map(\.category) == [.tomato])
            #expect(meal.shownRuleIDs == ["rule.acidicFoods.v1"])
            #expect(meal.checkIn?.severity == .mild)
            #expect(meal.checkIn?.symptoms == [.heartburn])
        }
    }

    /// Opens a store, runs the body, and closes it again — one "launch".
    private func withStore(
        at url: URL,
        _ body: (SwiftDataMealRepository) async throws -> Void
    ) async throws {
        let container = try ModelContainer(
            for: MealRecord.self, CheckInWindowRecord.self,
            configurations: ModelConfiguration(url: url)
        )
        try await body(SwiftDataMealRepository(container: container))
    }
}
