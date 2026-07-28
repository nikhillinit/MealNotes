import Foundation
import Testing
@testable import MealNotesCore

@Suite("Information precedence")
struct FactPrecedenceTests {
    let engine = GERDRulesEngine()

    @Test("Source trust ranks user > label > barcode > visual")
    func trustOrdering() {
        #expect(AssertionSource.userCorrection > AssertionSource.labelText)
        #expect(AssertionSource.labelText > AssertionSource.barcodeDatabase)
        #expect(AssertionSource.barcodeDatabase > AssertionSource.visualInference)
    }

    @Test("A user correction beats a confident visual guess")
    func userCorrectionWins() {
        let resolved = FactResolver.resolve([
            FoodFact(category: .caffeine, source: .visualInference, confidence: 0.99),
            .confirmed(.caffeine, isPresent: false)
        ])

        #expect(resolved.count == 1)
        #expect(resolved[0].source == .userCorrection)
        #expect(resolved[0].isPresent == false)
    }

    @Test("A user saying no removes the note a guess would have produced")
    func userCorrectionSuppressesWarning() {
        let facts: [FoodFact] = [
            FoodFact(category: .caffeine, source: .visualInference, confidence: 0.95),
            .confirmed(.caffeine, isPresent: false)
        ]
        #expect(engine.evaluate(facts: facts).warnings.isEmpty)
    }

    @Test("Label text beats a barcode record")
    func labelBeatsBarcode() {
        let resolved = FactResolver.resolve([
            FoodFact(category: .fullFatDairy, source: .barcodeDatabase, confidence: 0.9),
            FoodFact(category: .fullFatDairy, isPresent: false, source: .labelText, confidence: 0.8)
        ])

        #expect(resolved[0].source == .labelText)
        #expect(resolved[0].isPresent == false)
    }

    @Test("A barcode record beats a visual guess")
    func barcodeBeatsVisual() {
        let resolved = FactResolver.resolve([
            FoodFact(category: .chocolate, source: .visualInference, confidence: 1.0),
            FoodFact(category: .chocolate, source: .barcodeDatabase, confidence: 0.5)
        ])

        #expect(resolved[0].source == .barcodeDatabase)
    }

    @Test("A lower-trust claim never silently replaces a higher-trust one")
    func lowerTrustNeverReplaces() {
        let higher = FoodFact.confirmed(.tomato, isPresent: false)
        let lower = FoodFact(category: .tomato, source: .visualInference, confidence: 1.0)

        for ordering in [[higher, lower], [lower, higher]] {
            let audit = FactResolver.resolveWithAudit(ordering)
            #expect(audit.count == 1)
            #expect(audit[0].winner == higher)
            #expect(audit[0].overridden == [lower])
            #expect(audit[0].didOverrideLowerTrust)
            #expect(audit[0].wasContested)
        }
    }

    @Test("Within one source, the more confident claim wins")
    func confidenceBreaksTies() {
        let resolved = FactResolver.resolve([
            FoodFact(category: .spicy, source: .visualInference, confidence: 0.3, detail: "low"),
            FoodFact(category: .spicy, source: .visualInference, confidence: 0.8, detail: "high")
        ])

        #expect(resolved[0].detail == "high")
    }

    @Test("Resolution keeps one claim per category, in a stable order")
    func stableOrdering() {
        let facts: [FoodFact] = [
            .confirmed(.spicy, isPresent: true),
            .confirmed(.caffeine, isPresent: true),
            .confirmed(.tomato, isPresent: true)
        ]
        let forward = FactResolver.resolve(facts).map(\.category)
        let backward = FactResolver.resolve(facts.reversed()).map(\.category)

        #expect(forward == backward)
        #expect(Set(forward).count == forward.count)
    }

    @Test("The chocolate fixture keeps its barcode and label provenance")
    func fixtureProvenanceSurvives() throws {
        let response = try RecognitionResponseDecoder().decode(RecognitionFixture.packagedChocolateBar.payload)
        let resolved = FactResolver.resolve(response.candidateFacts)

        let chocolate = try #require(resolved.first { $0.category == .chocolate })
        #expect(chocolate.source == .barcodeDatabase)

        let fullFat = try #require(resolved.first { $0.category == .fullFatDairy })
        #expect(fullFat.source == .labelText)

        // Both fire notes, because both came from the package rather than a guess.
        let warnings = engine.evaluate(facts: response.candidateFacts).warnings.map(\.ruleID)
        #expect(warnings.contains("rule.chocolate.v1"))
        #expect(warnings.contains("rule.highFat.v1"))
    }
}
