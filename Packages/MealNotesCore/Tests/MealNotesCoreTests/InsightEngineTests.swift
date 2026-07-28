import Foundation
import Testing
@testable import MealNotesCore

@Suite("Insights")
struct InsightEngineTests {
    let engine = InsightEngine(calendar: TestDates.calendar)

    private func meals(
        count: Int,
        symptomatic: Int,
        categories: [FoodCategory] = [.caffeine],
        hour: Int = 8
    ) -> [MealSnapshot] {
        (0..<count).map { index in
            .stub(
                at: TestDates.at(hour, index),
                categories: categories,
                severity: index < symptomatic ? .mild : .fine
            )
        }
    }

    @Test("Too few observations says so plainly, with the count")
    func notEnoughInformation() {
        let insights = engine.insights(from: meals(count: 2, symptomatic: 2))

        #expect(insights.count == 1)
        #expect(insights[0].kind == .notEnoughInformation)
        #expect(insights[0].observationCount == 2)
        #expect(insights[0].headline == "There is not enough information yet to see a pattern.")
        #expect(insights[0].isActionable == false)
    }

    @Test("Meals with no answer are not counted as observations")
    func unansweredMealsAreNotObservations() {
        let answered = meals(count: 2, symptomatic: 2)
        let unanswered: [MealSnapshot] = (0..<10).map {
            .stub(at: TestDates.at(9, $0), categories: [.caffeine], severity: nil)
        }

        let insights = engine.insights(from: answered + unanswered)
        #expect(insights[0].kind == .notEnoughInformation)
        #expect(insights[0].observationCount == 2)
    }

    @Test("A category with enough observations is reported as a plain fraction")
    func reportsFraction() throws {
        let insights = engine.insights(from: meals(count: 5, symptomatic: 3))
        let insight = try #require(insights.first { $0.kind == .category(.caffeine) })

        #expect(insight.headline == "You reported symptoms 3 of the 5 times you recorded caffeine.")
        #expect(insight.observationCount == 5)
        #expect(insight.symptomCount == 3)
        #expect(insight.mealIDs.count == 5)
    }

    @Test("Every insight shows its observation count and a correlation note")
    func alwaysShowsCountsAndCaveat() {
        for insight in engine.insights(from: meals(count: 5, symptomatic: 3)) {
            #expect(insight.observationCount > 0)
            #expect(insight.detail.contains("\(insight.observationCount)"))
        }
        let insight = engine.insights(from: meals(count: 5, symptomatic: 3))
            .first { $0.kind == .category(.caffeine) }
        #expect(insight?.detail.contains(Insight.correlationNote) == true)
    }

    @Test("Small samples never show a percentage")
    func noPercentagesForSmallSamples() {
        for count in 3...9 {
            for insight in engine.insights(from: meals(count: count, symptomatic: 2)) {
                #expect(insight.detail.contains("%") == false, "sample of \(count) showed a percentage")
                #expect(insight.headline.contains("%") == false)
            }
        }
    }

    @Test("A large enough sample may add a percentage")
    func percentageOnceSampleIsLargeEnough() throws {
        let insights = engine.insights(from: meals(count: 10, symptomatic: 5))
        let insight = try #require(insights.first { $0.kind == .category(.caffeine) })

        #expect(insight.observationCount == InsightEngine.percentageSampleThreshold)
        #expect(insight.detail.contains("50%"))
    }

    @Test("A category with too few symptom reports is not raised")
    func needsEnoughSymptomReports() {
        let insights = engine.insights(from: meals(count: 6, symptomatic: 1))
        #expect(insights.map(\.kind) == [.notEnoughInformation])
    }

    @Test("Later meals are compared with earlier ones, with both counts shown")
    func eveningInsight() throws {
        var meals: [MealSnapshot] = []
        for index in 0..<5 {
            meals.append(.stub(at: TestDates.at(20, index), severity: index < 4 ? .moderate : .fine))
        }
        for index in 0..<5 {
            meals.append(.stub(at: TestDates.at(12, index), severity: index < 1 ? .mild : .fine))
        }

        let insight = try #require(engine.insights(from: meals).first { $0.kind == .eveningMeals })

        #expect(insight.headline == "Symptoms were more common after later meals.")
        #expect(insight.detail.contains("4 of 5"))
        #expect(insight.detail.contains("1 of 5"))
        #expect(insight.detail.contains(Insight.correlationNote))
    }

    @Test("No evening claim is made when later meals are not worse")
    func noEveningInsightWhenSimilar() {
        var meals: [MealSnapshot] = []
        for index in 0..<5 {
            meals.append(.stub(at: TestDates.at(20, index), severity: index < 2 ? .mild : .fine))
        }
        for index in 0..<5 {
            meals.append(.stub(at: TestDates.at(12, index), severity: index < 4 ? .mild : .fine))
        }

        #expect(engine.insights(from: meals).contains { $0.kind == .eveningMeals } == false)
    }

    @Test("An insight lists the meals behind it so they can be inspected")
    func mealsAreInspectable() throws {
        let sample = meals(count: 5, symptomatic: 3)
        let insight = try #require(
            engine.insights(from: sample).first { $0.kind == .category(.caffeine) }
        )

        #expect(Set(insight.mealIDs) == Set(sample.map(\.id)))
    }

    @Test("Insights never diagnose")
    func neverDiagnoses() {
        for insight in engine.insights(from: meals(count: 10, symptomatic: 6)) {
            #expect(SafetyWording.violations(in: insight.headline, context: insight.id).isEmpty)
            #expect(SafetyWording.violations(in: insight.detail, context: insight.id).isEmpty)
        }
    }

    // MARK: - Personal context

    @Test("Personal history is offered once there is enough of it")
    func personalNote() {
        let history = meals(count: 4, symptomatic: 3)
        let note = engine.personalNote(for: [.caffeine], meals: history)

        #expect(note == "You have recorded symptoms after caffeine 3 times before.")
    }

    @Test("Personal history stays quiet below the threshold")
    func personalNoteNeedsEvidence() {
        #expect(engine.personalNote(for: [.caffeine], meals: meals(count: 4, symptomatic: 1)) == nil)
        #expect(engine.personalNote(for: [.tomato], meals: meals(count: 4, symptomatic: 3)) == nil)
    }

    @Test("Personal history does not change the baseline note")
    func personalNoteDoesNotAlterWarnings() {
        // The rules engine has no access to history at all: same facts, same notes.
        let rules = GERDRulesEngine()
        let facts: [FoodFact] = [.confirmed(.caffeine, isPresent: true)]

        #expect(rules.evaluate(facts: facts).warnings.map(\.ruleID) == ["rule.caffeine.v1"])
        #expect(engine.personalNote(for: [.caffeine], meals: meals(count: 4, symptomatic: 3)) != nil)
        #expect(rules.evaluate(facts: facts).warnings.map(\.ruleID) == ["rule.caffeine.v1"])
    }
}
