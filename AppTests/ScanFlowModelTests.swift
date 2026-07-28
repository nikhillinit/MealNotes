import Foundation
import MealNotesCore
import Testing
@testable import MealNotes

/// Exercises the whole capture-to-logged journey through the flow model, with
/// fixtures standing in for a camera and a recognition service.
@MainActor
@Suite("Scan flow")
struct ScanFlowModelTests {
    private static let noon = CalendarSupport.date(2026, 3, 10, 12, 0)

    private func makeEnvironment(offline: Bool = false) throws -> AppEnvironment {
        AppEnvironment(
            repository: SwiftDataMealRepository(container: try MealNotesSchema.inMemoryContainer()),
            scheduler: InMemoryCheckInScheduler(),
            recognitionClient: MockRecognitionClient(offline: offline),
            dates: FixedDateProvider(Self.noon)
        )
    }

    @Test("Tea: one question, then one note, then a logged meal")
    func teaJourney() async throws {
        let environment = try makeEnvironment()
        let model = ScanFlowModel(environment: environment)

        await model.begin(fixture: .caffeinatedTea)

        #expect(model.stage == .asking)
        #expect(model.itemName == "Black tea")
        #expect(model.questions.count == 1)
        #expect(model.currentQuestion?.question == "Was the tea caffeinated?")
        // Nothing is claimed before the question is answered.
        #expect(model.evaluation.hasWarning == false)

        model.answerCurrentQuestion(true)

        #expect(model.stage == .result)
        #expect(model.evaluation.displayWarnings.map(\.ruleID) == ["rule.caffeine.v1"])

        await model.confirmConsumption()

        #expect(model.stage == .logged)
        let meals = try environment.repository.allMeals()
        #expect(meals.count == 1)
        #expect(meals[0].displayName == "Black tea")
        #expect(meals[0].shownRuleIDs == ["rule.caffeine.v1"])
        #expect(meals[0].consumedAt == Self.noon)
        #expect(meals[0].retainedPhoto == false)
    }

    @Test("Answering no leaves nothing to say")
    func teaAnsweredNo() async throws {
        let model = ScanFlowModel(environment: try makeEnvironment())
        await model.begin(fixture: .caffeinatedTea)
        model.answerCurrentQuestion(false)

        #expect(model.stage == .result)
        #expect(model.evaluation.hasWarning == false)
    }

    @Test("Not being sure asserts nothing either way")
    func unsureAssertsNothing() async throws {
        let model = ScanFlowModel(environment: try makeEnvironment())
        await model.begin(fixture: .caffeinatedTea)
        model.skipCurrentQuestion()

        #expect(model.stage == .result)
        #expect(model.evaluation.hasWarning == false)
        #expect(model.facts.allSatisfy { $0.source != .userCorrection })
    }

    @Test("A meal with nothing to flag goes straight to the result")
    func salmonJourney() async throws {
        let model = ScanFlowModel(environment: try makeEnvironment())
        await model.begin(fixture: .salmonWithCouscous)

        #expect(model.stage == .result)
        #expect(model.questions.isEmpty)
        #expect(model.evaluation.hasWarning == false)
        #expect(model.itemName == "Salmon with couscous")
        #expect(model.limitations.isEmpty == false)
    }

    @Test("Tomato is flagged straight away while spice is asked about")
    func pastaJourney() async throws {
        let model = ScanFlowModel(environment: try makeEnvironment())
        await model.begin(fixture: .tomatoSpicyPasta)

        #expect(model.stage == .asking)
        #expect(model.questions.map(\.category) == [.spicy])
        #expect(model.evaluation.warnings.map(\.ruleID) == ["rule.acidicFoods.v1"])

        model.answerCurrentQuestion(true)

        #expect(model.evaluation.displayWarnings.map(\.ruleID) == ["rule.acidicFoods.v1", "rule.spicy.v1"])
    }

    @Test("A packaged product uses what the label and barcode say")
    func packagedProduct() async throws {
        let model = ScanFlowModel(environment: try makeEnvironment())
        await model.begin(fixture: .packagedChocolateBar)

        #expect(model.stage == .result)
        #expect(model.questions.isEmpty)
        #expect(model.evaluation.warnings.map(\.ruleID) == ["rule.chocolate.v1", "rule.highFat.v1"])
        // Only two are shown, even though both were recorded.
        #expect(model.evaluation.displayWarnings.count == 2)
    }

    @Test("An unusable response falls back to typing, with no note")
    func malformedFallsBackToTyping() async throws {
        let environment = try makeEnvironment()
        let model = ScanFlowModel(environment: environment)

        await model.begin(fixture: .malformedResponse)

        #expect(model.stage == .manualEntry)
        #expect(model.manualEntryReason != nil)
        #expect(model.provenance.usedManualEntry)
        #expect(model.provenance.repairAttempted)
        #expect(model.evaluation.hasWarning == false)

        model.typedName = "Leftover curry"
        await model.logTypedEntry()

        #expect(model.stage == .logged)
        let meals = try environment.repository.allMeals()
        #expect(meals[0].displayName == "Leftover curry")
        #expect(meals[0].shownRuleIDs.isEmpty)
        #expect(meals[0].provenance.usedManualEntry)
    }

    @Test("Offline falls back to typing too")
    func offlineFallsBackToTyping() async throws {
        let model = ScanFlowModel(environment: try makeEnvironment(offline: true))
        await model.begin(fixture: .caffeinatedTea)

        #expect(model.stage == .manualEntry)
        #expect(model.manualEntryReason == .serviceUnavailable)
    }

    @Test("A blank name is not logged")
    func blankNameIsRejected() async throws {
        let environment = try makeEnvironment()
        let model = ScanFlowModel(environment: environment)
        model.beginManualEntry()

        model.typedName = "   "
        await model.logTypedEntry()

        #expect(model.stage == .manualEntry)
        #expect(try environment.repository.allMeals().isEmpty)
    }

    @Test("A low-confidence guess is still offered, and flagged as uncertain")
    func lowConfidenceIsFlagged() async throws {
        let model = ScanFlowModel(environment: try makeEnvironment())
        await model.begin(fixture: .unknownItem)

        #expect(model.stage == .result)
        #expect(model.identificationIsUncertain)
        #expect(model.evaluation.hasWarning == false)
    }

    // MARK: - Corrections

    @Test("Correcting the name and ingredients is recorded and changes the notes")
    func correctionsChangeTheResult() async throws {
        let environment = try makeEnvironment()
        let model = ScanFlowModel(environment: environment)
        await model.begin(fixture: .salmonWithCouscous)

        #expect(model.evaluation.hasWarning == false)

        model.applyCorrection(name: "Salmon with a creamy sauce", categories: [.fullFatDairy])

        #expect(model.itemName == "Salmon with a creamy sauce")
        #expect(model.evaluation.displayWarnings.map(\.ruleID) == ["rule.highFat.v1"])
        #expect(model.corrections.count == 2)

        await model.confirmConsumption()

        let meal = try #require(try environment.repository.allMeals().first)
        #expect(meal.displayName == "Salmon with a creamy sauce")
        #expect(meal.corrections.count == 2)
        #expect(meal.shownRuleIDs == ["rule.highFat.v1"])
    }

    @Test("Removing an ingredient removes the note it produced")
    func correctionCanRemoveANote() async throws {
        let model = ScanFlowModel(environment: try makeEnvironment())
        await model.begin(fixture: .tomatoSpicyPasta)
        model.answerCurrentQuestion(true)

        #expect(model.evaluation.displayWarnings.count == 2)

        model.applyCorrection(name: model.itemName, categories: [])

        #expect(model.evaluation.hasWarning == false)
    }
}

@MainActor
@Suite("Home screen state")
struct AppEnvironmentTests {
    private static let noon = CalendarSupport.date(2026, 3, 10, 12, 0)

    private func makeEnvironment() throws -> AppEnvironment {
        AppEnvironment(
            repository: SwiftDataMealRepository(container: try MealNotesSchema.inMemoryContainer()),
            scheduler: InMemoryCheckInScheduler(),
            recognitionClient: MockRecognitionClient(),
            insightEngine: InsightEngine(calendar: CalendarSupport.utc),
            dates: FixedDateProvider(Self.noon)
        )
    }

    @Test("A logged meal shows up on the home screen")
    func refreshPicksUpMeals() async throws {
        let environment = try makeEnvironment()
        let model = ScanFlowModel(environment: environment)

        await model.begin(fixture: .salmonWithCouscous)
        await model.confirmConsumption()

        #expect(environment.totalMealCount == 1)
        #expect(environment.recentMeals.map(\.displayName) == ["Salmon with couscous"])
        // The check-in is two hours away, so nothing is due yet.
        #expect(environment.dueCheckIns.isEmpty)
    }

    @Test("Bringing a check-in forward makes it due without waiting")
    func simulateDueCheckIn() async throws {
        let environment = try makeEnvironment()
        let model = ScanFlowModel(environment: environment)
        await model.begin(fixture: .salmonWithCouscous)
        await model.confirmConsumption()

        environment.simulateDueCheckIn()

        #expect(environment.dueCheckIns.count == 1)

        let window = try #require(environment.dueCheckIns.first)
        await environment.recordCheckIn(
            windowID: window.id, severity: .mild, symptoms: [.heartburn], urgentSymptoms: []
        )

        #expect(environment.dueCheckIns.isEmpty)
        #expect(environment.recentMeals.first?.checkIn?.severity == .mild)
        #expect(environment.urgentAdvisory == nil)
    }

    @Test("An urgent symptom raises the advisory for the app to show")
    func urgentAdvisoryIsRaised() async throws {
        let environment = try makeEnvironment()
        let model = ScanFlowModel(environment: environment)
        await model.begin(fixture: .salmonWithCouscous)
        await model.confirmConsumption()
        environment.simulateDueCheckIn()

        let window = try #require(environment.dueCheckIns.first)
        await environment.recordCheckIn(
            windowID: window.id, severity: .severe, symptoms: [], urgentSymptoms: [.difficultySwallowing]
        )

        #expect(environment.urgentAdvisory?.symptoms == [.difficultySwallowing])
    }

    @Test("Insights start out honest about having too little to go on")
    func insightsStartEmpty() async throws {
        let environment = try makeEnvironment()
        environment.refresh()

        #expect(environment.insights.map(\.kind) == [.notEnoughInformation])
    }
}
