import Foundation
import Testing
@testable import MealNotesCore

@Suite("Rule catalog metadata")
struct RuleCatalogTests {
    let rules = GERDRuleCatalog.defaultRules

    @Test("Every rule has a stable, unique identifier")
    func uniqueStableIDs() {
        let ids = rules.map(\.id)
        #expect(Set(ids).count == ids.count)
        for id in ids {
            #expect(id.hasPrefix("rule."), "\(id) should be namespaced")
            #expect(id.range(of: #"\.v\d+$"#, options: .regularExpression) != nil, "\(id) should be versioned")
        }
    }

    @Test("Every rule cites at least one authoritative source with a usable URL")
    func everyRuleHasSources() {
        for rule in rules {
            #expect(!rule.sources.isEmpty, "\(rule.id) has no source")
            for source in rule.sources {
                #expect(!source.title.isEmpty)
                #expect(source.url.scheme == "https", "\(rule.id) source must be https")
                #expect(source.url.host() != nil)
            }
        }
    }

    @Test("Sources are limited to the guidance the app is built on")
    func sourcesAreExpected() {
        let allowedHosts: Set<String> = ["www.niddk.nih.gov", "gi.org"]
        for rule in rules {
            for source in rule.sources {
                #expect(allowedHosts.contains(source.url.host() ?? ""), "\(rule.id) cites \(source.url)")
            }
        }
    }

    @Test("Every rule carries evidence category, review date, matchers and copy")
    func everyRuleIsComplete() {
        for rule in rules {
            #expect(!rule.matchers.isEmpty, "\(rule.id) matches nothing")
            #expect(!rule.title.isEmpty)
            #expect(!rule.explanation.isEmpty, "\(rule.id) has no reason")
            #expect(!rule.suggestion.isEmpty, "\(rule.id) has no suggestion")
            #expect(EvidenceCategory.allCases.contains(rule.evidence))
            #expect(rule.lastReviewed == GERDRuleCatalog.reviewedOn)
        }
    }

    @Test("The catalog covers the commonly cited categories")
    func expectedCoverage() {
        let matched = rules.reduce(into: Set<FoodCategory>()) { $0.formUnion($1.matchers) }
        let expected: Set<FoodCategory> = [
            .caffeine, .chocolate, .alcohol, .mint, .tomato, .citrus,
            .spicy, .highFat, .largePortion
        ]
        #expect(expected.isSubset(of: matched))
    }

    @Test("Categories held back from the baseline stay unmatched")
    func intentionallyUnmatchedStaysUnmatched() {
        let matched = rules.reduce(into: Set<FoodCategory>()) { $0.formUnion($1.matchers) }
        #expect(matched.isDisjoint(with: GERDRuleCatalog.intentionallyUnmatched))
    }

    @Test("Each rule offers one reason and one adjustment, not a lecture")
    func copyStaysShort() {
        for rule in rules {
            #expect(rule.explanation.count <= 140, "\(rule.id) reason is too long")
            #expect(rule.suggestion.count <= 140, "\(rule.id) suggestion is too long")
        }
    }
}

@Suite("Wording guardrails")
struct SafetyWordingTests {
    @Test("No rule labels a food or claims certainty")
    func rulesAvoidBannedWording() {
        let violations = SafetyWording.audit(GERDRuleCatalog.defaultRules)
        #expect(violations.isEmpty, "\(violations.map(\.description))")
    }

    @Test("No rule shows a percentage or a risk score")
    func rulesAvoidPseudoPrecision() {
        for rule in GERDRuleCatalog.defaultRules {
            #expect(SafetyWording.containsRiskScore(rule.explanation) == false)
            #expect(SafetyWording.containsRiskScore(rule.suggestion) == false)
            #expect(SafetyWording.containsRiskScore(rule.title) == false)
        }
    }

    @Test("Warnings put on screen carry no banned wording either")
    func warningsAvoidBannedWording() {
        let engine = GERDRulesEngine()
        for category in FoodCategory.allCases {
            let evaluation = engine.evaluate(facts: [.confirmed(category, isPresent: true)])
            for warning in evaluation.warnings {
                let fields = [warning.title, warning.reason, warning.suggestion, warning.heading]
                for field in fields {
                    #expect(SafetyWording.violations(in: field, context: warning.ruleID).isEmpty)
                    #expect(SafetyWording.containsRiskScore(field) == false)
                }
            }
        }
    }

    @Test("The banned-word check matches whole words only", arguments: [
        ("This is safe to eat", true),
        ("Food safety matters", false),
        ("A treatment plan", true),
        ("Retreating from the table", false),
        ("This will cause symptoms", true),
        ("This can bring on symptoms", false)
    ])
    func wholeWordMatching(text: String, expectViolation: Bool) {
        let violations = SafetyWording.violations(in: text, context: "test")
        #expect(violations.isEmpty != expectViolation, "\(text) → \(violations.map(\.phrase))")
    }

    @Test("Insight wording avoids banned phrasing")
    func insightsAvoidBannedWording() {
        let engine = InsightEngine(calendar: TestDates.calendar)
        var meals: [MealSnapshot] = []
        for index in 0..<6 {
            meals.append(
                .stub(
                    at: TestDates.at(8, index),
                    categories: [.caffeine],
                    severity: index < 4 ? .mild : .fine
                )
            )
        }

        let insights = engine.insights(from: meals)
        #expect(!insights.isEmpty)
        for insight in insights {
            #expect(SafetyWording.violations(in: insight.headline, context: insight.id).isEmpty)
            #expect(SafetyWording.violations(in: insight.detail, context: insight.id).isEmpty)
        }
    }

    @Test("Clarification questions avoid banned phrasing")
    func questionsAvoidBannedWording() {
        for category in FoodCategory.allCases {
            let question = ClarificationPlanner.defaultQuestion(for: category)
            #expect(SafetyWording.violations(in: question, context: category.rawValue).isEmpty)
        }
    }
}
