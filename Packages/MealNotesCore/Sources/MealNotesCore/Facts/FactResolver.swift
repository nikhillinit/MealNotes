import Foundation

/// What happened to the competing claims about one category.
public struct FactResolution: Sendable, Hashable {
    public let category: FoodCategory
    public let winner: FoodFact
    /// Claims that lost, in the order they were beaten.
    public let overridden: [FoodFact]

    /// True when a claim from a *less* trusted source was set aside.
    public var didOverrideLowerTrust: Bool {
        overridden.contains { $0.source < winner.source }
    }

    /// True when two sources disagreed about whether something was present.
    public var wasContested: Bool {
        overridden.contains { $0.isPresent != winner.isPresent }
    }
}

/// Applies the app's information-precedence contract.
///
/// For each category exactly one claim survives: the one from the most trusted
/// source. A visual guess can never displace a label reading, a barcode record,
/// or something the user said — including when the user says an ingredient is
/// *not* there.
public enum FactResolver {
    public static func resolve(_ facts: [FoodFact]) -> [FoodFact] {
        resolveWithAudit(facts).map(\.winner)
    }

    public static func resolveWithAudit(_ facts: [FoodFact]) -> [FactResolution] {
        var winners: [FoodCategory: FoodFact] = [:]
        var overridden: [FoodCategory: [FoodFact]] = [:]

        // Walked in order, because order carries meaning: a second answer about
        // the same thing is a correction of the first.
        for fact in facts {
            guard let current = winners[fact.category] else {
                winners[fact.category] = fact
                continue
            }
            if supersedes(fact, current) {
                winners[fact.category] = fact
                overridden[fact.category, default: []].append(current)
            } else {
                overridden[fact.category, default: []].append(fact)
            }
        }

        // Emitted in the enum's own order so the result is stable.
        return FoodCategory.allCases.compactMap { category in
            guard let winner = winners[category] else { return nil }
            return FactResolution(
                category: category,
                winner: winner,
                overridden: overridden[category] ?? []
            )
        }
    }

    /// A later claim wins only if it is at least as trustworthy as the standing one.
    ///
    /// Trust dominates: a visual guess never displaces a label reading, however
    /// late it arrives. Within the same source and confidence the newer statement
    /// wins, which is what lets the user change their mind — answering "yes" and
    /// then correcting it to "no" leaves "no" standing.
    private static func supersedes(_ candidate: FoodFact, _ current: FoodFact) -> Bool {
        if candidate.source != current.source { return candidate.source > current.source }
        return candidate.confidence >= current.confidence
    }
}
