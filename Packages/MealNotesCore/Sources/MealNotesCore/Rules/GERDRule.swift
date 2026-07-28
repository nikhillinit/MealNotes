import Foundation

/// Where a rule's wording comes from. Every rule must cite at least one.
public struct RuleSource: Sendable, Hashable, Codable {
    public let title: String
    public let url: URL

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }

    public static let niddkEating = RuleSource(
        title: "NIDDK — Eating, Diet, & Nutrition for GER & GERD",
        url: URL(string: "https://www.niddk.nih.gov/health-information/digestive-diseases/acid-reflux-ger-gerd-adults/eating-diet-nutrition")!
    )

    public static let acgAcidReflux = RuleSource(
        title: "American College of Gastroenterology — Acid Reflux",
        url: URL(string: "https://gi.org/topics/acid-reflux/")!
    )

    public static let niddkSymptoms = RuleSource(
        title: "NIDDK — Symptoms & Causes of GER & GERD",
        url: URL(string: "https://www.niddk.nih.gov/health-information/digestive-diseases/acid-reflux-ger-gerd-adults/symptoms-causes")!
    )
}

/// How much weight the underlying guidance carries.
///
/// Shown to the user so a widely repeated suggestion is not mistaken for a
/// settled finding.
public enum EvidenceCategory: String, Sendable, Hashable, Codable, CaseIterable {
    /// Named in mainstream patient guidance from NIDDK or the ACG.
    case commonlyCited
    /// Mentioned in guidance, but studies disagree.
    case mixedEvidence
    /// Guidance itself says this differs a lot from person to person.
    case individualVariation

    public var displayName: String {
        switch self {
        case .commonlyCited: "Commonly cited in patient guidance"
        case .mixedEvidence: "Evidence is mixed"
        case .individualVariation: "Differs from person to person"
        }
    }
}

/// One deterministic rule mapping food properties to a calm note.
///
/// A rule never decides anything on its own: it fires only when a fact about the
/// meal was asserted by a trusted-enough source. See ``GERDRulesEngine``.
public struct GERDRule: Sendable, Hashable, Identifiable {
    /// Stable across releases — recorded on every meal so an old record can
    /// always be explained.
    public let id: String
    public let title: String
    public let matchers: Set<FoodCategory>
    /// One short reason, in plain language.
    public let explanation: String
    /// One practical alternative or adjustment.
    public let suggestion: String
    public let sources: [RuleSource]
    public let evidence: EvidenceCategory
    public let lastReviewed: Date

    public init(
        id: String,
        title: String,
        matchers: Set<FoodCategory>,
        explanation: String,
        suggestion: String,
        sources: [RuleSource],
        evidence: EvidenceCategory,
        lastReviewed: Date
    ) {
        self.id = id
        self.title = title
        self.matchers = matchers
        self.explanation = explanation
        self.suggestion = suggestion
        self.sources = sources
        self.evidence = evidence
        self.lastReviewed = lastReviewed
    }
}

/// A note ready to be shown on screen.
public struct GERDWarning: Sendable, Hashable, Identifiable {
    /// The only heading the app ever uses above a note.
    public static let heading = "Heads up"

    public let ruleID: String
    public let title: String
    public let reason: String
    public let suggestion: String
    public let matchedCategories: [FoodCategory]
    public let sources: [RuleSource]
    public let evidence: EvidenceCategory
    public let lastReviewed: Date

    public var id: String { ruleID }

    public var heading: String { Self.heading }

    init(rule: GERDRule, matchedCategories: [FoodCategory]) {
        self.ruleID = rule.id
        self.title = rule.title
        self.reason = rule.explanation
        self.suggestion = rule.suggestion
        self.matchedCategories = matchedCategories
        self.sources = rule.sources
        self.evidence = rule.evidence
        self.lastReviewed = rule.lastReviewed
    }
}
