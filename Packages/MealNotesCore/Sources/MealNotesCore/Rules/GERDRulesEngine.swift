import Foundation

/// Facts about a meal that come from the clock rather than from the picture.
public struct MealContext: Sendable, Hashable {
    public let consumedAt: Date
    public let calendar: Calendar

    public init(consumedAt: Date, calendar: Calendar = .current) {
        self.consumedAt = consumedAt
        self.calendar = calendar
    }
}

public struct GERDEvaluation: Sendable, Hashable {
    /// Every rule that fired, in catalog order. Recorded on the meal.
    public let warnings: [GERDWarning]
    /// Present-but-unconfirmed claims that would change the notes if confirmed.
    /// These become the clarification questions.
    public let unconfirmedMaterialFacts: [FoodFact]
    /// The facts after precedence was applied — what the meal is actually stored with.
    public let resolvedFacts: [FoodFact]

    /// What goes on screen. Capped so the result stays short and calm.
    public var displayWarnings: [GERDWarning] {
        Array(warnings.prefix(GERDRulesEngine.maxDisplayedWarnings))
    }

    public var hasWarning: Bool { !warnings.isEmpty }

    public static let none = GERDEvaluation(warnings: [], unconfirmedMaterialFacts: [], resolvedFacts: [])
}

/// Turns facts about a meal into zero or more notes.
///
/// This is the only thing in the app allowed to decide that a note is shown.
/// A recognition provider can propose what a food *is*; it cannot propose what
/// that means. Two consequences follow, and both are tested:
///
/// - The engine is a pure function. Same facts in, same notes out.
/// - A note requires a fact from a trusted-enough source. A shaky visual guess
///   produces a *question*, never a note.
public struct GERDRulesEngine: Sendable {
    /// At most two notes on screen. The rest are still recorded on the meal.
    public static let maxDisplayedWarnings = 2
    /// Meals at or after this hour match `rule.lateEvening.v1`.
    public static let lateEveningHour = 21

    public let rules: [GERDRule]

    public init(rules: [GERDRule] = GERDRuleCatalog.defaultRules) {
        self.rules = rules
    }

    public func evaluate(facts: [FoodFact], context: MealContext? = nil) -> GERDEvaluation {
        // Resolve here rather than trusting the caller: precedence is part of
        // the safety contract, not a caller convenience.
        let resolved = FactResolver.resolve(facts)

        var confirmedCategories: Set<FoodCategory> = []
        var unconfirmed: [FoodFact] = []
        for fact in resolved where fact.isPresent {
            if fact.isStrongEnoughToWarn {
                confirmedCategories.insert(fact.category)
            } else {
                unconfirmed.append(fact)
            }
        }

        if let context, isLateEvening(context) {
            confirmedCategories.insert(.lateEvening)
        }

        var warnings: [GERDWarning] = []
        for rule in rules {
            let matched = rule.matchers.intersection(confirmedCategories)
            guard !matched.isEmpty else { continue }
            warnings.append(
                GERDWarning(
                    rule: rule,
                    matchedCategories: matched.sorted { $0.rawValue < $1.rawValue }
                )
            )
        }

        let firedRuleIDs = Set(warnings.map(\.ruleID))

        // A question is only worth asking if the answer could change what is
        // shown. If the rule it would trigger has already fired for another
        // reason, confirming it adds nothing.
        let material = unconfirmed.filter { fact in
            rules.contains { rule in
                rule.matchers.contains(fact.category) && !firedRuleIDs.contains(rule.id)
            }
        }

        return GERDEvaluation(
            warnings: warnings,
            unconfirmedMaterialFacts: material,
            resolvedFacts: resolved
        )
    }

    func isLateEvening(_ context: MealContext) -> Bool {
        context.calendar.component(.hour, from: context.consumedAt) >= Self.lateEveningHour
    }

    public func rule(withID id: String) -> GERDRule? {
        rules.first { $0.id == id }
    }
}
