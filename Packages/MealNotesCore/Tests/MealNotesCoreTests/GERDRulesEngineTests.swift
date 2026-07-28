import Foundation
import Testing
@testable import MealNotesCore

@Suite("GERD rule matching")
struct GERDRulesEngineTests {
    let engine = GERDRulesEngine()

    @Test("A confirmed category fires its rule")
    func confirmedCategoryFires() {
        let evaluation = engine.evaluate(facts: [.confirmed(.caffeine, isPresent: true)])

        #expect(evaluation.warnings.map(\.ruleID) == ["rule.caffeine.v1"])
        #expect(evaluation.warnings.first?.heading == "Heads up")
        #expect(evaluation.unconfirmedMaterialFacts.isEmpty)
    }

    @Test("No facts means no note at all")
    func noFactsNoWarning() {
        #expect(engine.evaluate(facts: []).warnings.isEmpty)
        #expect(engine.evaluate(facts: []).hasWarning == false)
    }

    @Test("An explicit absence does not fire a rule")
    func absenceDoesNotFire() {
        let evaluation = engine.evaluate(facts: [.confirmed(.caffeine, isPresent: false)])
        #expect(evaluation.warnings.isEmpty)
        #expect(evaluation.unconfirmedMaterialFacts.isEmpty)
    }

    @Test("A low-confidence visual guess asks instead of warning")
    func lowConfidenceVisualAsks() {
        let facts = [FoodFact(category: .caffeine, source: .visualInference, confidence: 0.55)]
        let evaluation = engine.evaluate(facts: facts)

        #expect(evaluation.warnings.isEmpty)
        #expect(evaluation.unconfirmedMaterialFacts.map(\.category) == [.caffeine])
    }

    @Test("A high-confidence visual guess is enough to warn")
    func highConfidenceVisualWarns() {
        let facts = [FoodFact(category: .tomato, source: .visualInference, confidence: 0.88)]
        let evaluation = engine.evaluate(facts: facts)

        #expect(evaluation.warnings.map(\.ruleID) == ["rule.acidicFoods.v1"])
        #expect(evaluation.unconfirmedMaterialFacts.isEmpty)
    }

    @Test("The visual confidence boundary is inclusive")
    func confidenceBoundary() {
        let atThreshold = FoodFact(
            category: .tomato, source: .visualInference,
            confidence: FoodFact.warrantableVisualConfidence
        )
        let justBelow = FoodFact(
            category: .tomato, source: .visualInference,
            confidence: FoodFact.warrantableVisualConfidence - 0.01
        )

        #expect(engine.evaluate(facts: [atThreshold]).hasWarning)
        #expect(engine.evaluate(facts: [justBelow]).hasWarning == false)
    }

    // MARK: - Dairy nuance

    @Test("Plain dairy is not treated as something to flag")
    func plainDairyDoesNotWarn() {
        let evaluation = engine.evaluate(facts: [.confirmed(.dairy, isPresent: true)])

        #expect(evaluation.warnings.isEmpty)
        // Nor should it produce a question: no rule would fire either way.
        #expect(evaluation.unconfirmedMaterialFacts.isEmpty)
    }

    @Test("Dairy that is high in fat is flagged for the fat")
    func fullFatDairyWarnsViaFatRule() {
        let evaluation = engine.evaluate(facts: [.confirmed(.fullFatDairy, isPresent: true)])

        #expect(evaluation.warnings.map(\.ruleID) == ["rule.highFat.v1"])
        #expect(evaluation.warnings.first?.title == "Higher-fat food")
    }

    @Test("Milk alongside full-fat dairy still only fires the fat rule once")
    func dairyAndFullFatTogether() {
        let evaluation = engine.evaluate(facts: [
            .confirmed(.dairy, isPresent: true),
            .confirmed(.fullFatDairy, isPresent: true)
        ])

        #expect(evaluation.warnings.map(\.ruleID) == ["rule.highFat.v1"])
    }

    @Test("No rule matches plain dairy in the catalog")
    func catalogNeverMatchesPlainDairy() {
        for rule in GERDRuleCatalog.defaultRules {
            #expect(rule.matchers.contains(.dairy) == false, "\(rule.id) must not match plain dairy")
        }
        #expect(GERDRuleCatalog.intentionallyUnmatched.contains(.dairy))
    }

    // MARK: - Ordering and display cap

    @Test("Notes come back in catalog order and only two are shown")
    func displayCap() {
        let evaluation = engine.evaluate(facts: [
            .confirmed(.spicy, isPresent: true),
            .confirmed(.tomato, isPresent: true),
            .confirmed(.caffeine, isPresent: true),
            .confirmed(.largePortion, isPresent: true)
        ])

        #expect(evaluation.warnings.count == 4)
        #expect(evaluation.warnings.map(\.ruleID) == [
            "rule.caffeine.v1", "rule.acidicFoods.v1", "rule.spicy.v1", "rule.largeMeal.v1"
        ])
        // On screen the result stays short, but the record keeps everything.
        #expect(evaluation.displayWarnings.count == GERDRulesEngine.maxDisplayedWarnings)
        #expect(evaluation.displayWarnings.map(\.ruleID) == ["rule.caffeine.v1", "rule.acidicFoods.v1"])
    }

    @Test("The engine is a pure function of its inputs")
    func deterministic() {
        let facts: [FoodFact] = [
            FoodFact(category: .tomato, source: .visualInference, confidence: 0.9),
            .confirmed(.spicy, isPresent: true)
        ]
        #expect(engine.evaluate(facts: facts) == engine.evaluate(facts: facts.reversed()))
    }

    // MARK: - Context

    @Test("A late meal fires the evening rule")
    func lateEveningFires() {
        let context = MealContext(consumedAt: TestDates.at(21, 30), calendar: TestDates.calendar)
        let evaluation = engine.evaluate(facts: [], context: context)

        #expect(evaluation.warnings.map(\.ruleID) == ["rule.lateEvening.v1"])
    }

    @Test("An early evening meal does not")
    func earlyEveningDoesNotFire() {
        let context = MealContext(consumedAt: TestDates.at(19, 0), calendar: TestDates.calendar)
        #expect(engine.evaluate(facts: [], context: context).warnings.isEmpty)
    }

    // MARK: - Materiality

    @Test("A question is skipped when its rule already fired for another reason")
    func skipsQuestionThatCannotChangeAnything() {
        // `fried` already fires the high-fat rule; confirming full-fat dairy
        // would fire the same rule, so asking changes nothing on screen.
        let evaluation = engine.evaluate(facts: [
            .confirmed(.fried, isPresent: true),
            FoodFact(category: .fullFatDairy, source: .visualInference, confidence: 0.4)
        ])

        #expect(evaluation.warnings.map(\.ruleID) == ["rule.highFat.v1"])
        #expect(evaluation.unconfirmedMaterialFacts.isEmpty)
    }

    @Test("A question is asked when its rule has not fired")
    func asksWhenItWouldChangeTheResult() {
        let evaluation = engine.evaluate(facts: [
            FoodFact(category: .tomato, source: .visualInference, confidence: 0.9),
            FoodFact(category: .spicy, source: .visualInference, confidence: 0.5)
        ])

        #expect(evaluation.warnings.map(\.ruleID) == ["rule.acidicFoods.v1"])
        #expect(evaluation.unconfirmedMaterialFacts.map(\.category) == [.spicy])
    }
}
