import Foundation

/// The baseline rule set.
///
/// Wording is deliberately hedged ("for some people", "may", "can") because the
/// underlying guidance is hedged. Nothing here claims that a food will cause
/// symptoms, and nothing labels a food as one thing or another — see
/// ``SafetyWording``, which the tests enforce against every string below.
///
/// Order matters: it is the display order, and only the first
/// ``GERDRulesEngine/maxDisplayedWarnings`` notes are put on screen.
public enum GERDRuleCatalog {
    /// Bumped whenever wording or matchers change, so stored meals stay explainable.
    public static let reviewedOn = CalendarSupport.date(2026, 7, 27)

    public static let defaultRules: [GERDRule] = [
        GERDRule(
            id: "rule.caffeine.v1",
            title: "Caffeine",
            matchers: [.caffeine],
            explanation: "Caffeine can make reflux symptoms worse for some people.",
            suggestion: "If you would like, decaf or a smaller cup is an easy swap.",
            sources: [.niddkEating, .acgAcidReflux],
            evidence: .commonlyCited,
            lastReviewed: reviewedOn
        ),
        GERDRule(
            id: "rule.chocolate.v1",
            title: "Chocolate",
            matchers: [.chocolate],
            explanation: "Chocolate is often mentioned as something that can bring on reflux.",
            suggestion: "A smaller piece, or having it earlier in the day, may sit more easily.",
            sources: [.niddkEating, .acgAcidReflux],
            evidence: .commonlyCited,
            lastReviewed: reviewedOn
        ),
        GERDRule(
            id: "rule.alcohol.v1",
            title: "Alcohol",
            matchers: [.alcohol],
            explanation: "Alcohol can relax the muscle at the top of the stomach, which makes reflux more likely.",
            suggestion: "A smaller amount, or a night without it, may make a difference.",
            sources: [.niddkEating, .acgAcidReflux],
            evidence: .commonlyCited,
            lastReviewed: reviewedOn
        ),
        GERDRule(
            id: "rule.acidicFoods.v1",
            title: "Acidic foods",
            matchers: [.tomato, .citrus],
            explanation: "Tomato and citrus are acidic, and can bring on symptoms for some people.",
            suggestion: "A smaller portion, or a version without the acidic part, may feel easier.",
            sources: [.niddkEating, .acgAcidReflux],
            evidence: .commonlyCited,
            lastReviewed: reviewedOn
        ),
        GERDRule(
            id: "rule.spicy.v1",
            title: "Spicy food",
            matchers: [.spicy],
            explanation: "Spicy food can bring on reflux symptoms for some people.",
            suggestion: "A milder version, or less of the sauce, is worth a try.",
            sources: [.niddkEating, .acgAcidReflux],
            evidence: .commonlyCited,
            lastReviewed: reviewedOn
        ),
        GERDRule(
            id: "rule.highFat.v1",
            title: "Higher-fat food",
            matchers: [.highFat, .fried, .fullFatDairy],
            explanation: "Higher-fat and fried foods stay in the stomach longer, which can make reflux more likely.",
            suggestion: "A lighter cooking method, or a smaller portion, may help.",
            sources: [.niddkEating, .acgAcidReflux],
            evidence: .commonlyCited,
            lastReviewed: reviewedOn
        ),
        GERDRule(
            id: "rule.largeMeal.v1",
            title: "Large meal",
            matchers: [.largePortion],
            explanation: "Large meals can make reflux more likely.",
            suggestion: "Smaller meals a little more often may be gentler.",
            sources: [.niddkEating, .niddkSymptoms],
            evidence: .commonlyCited,
            lastReviewed: reviewedOn
        ),
        GERDRule(
            id: "rule.mint.v1",
            title: "Mint",
            matchers: [.mint],
            explanation: "Peppermint is often listed among things that can bring on reflux.",
            suggestion: "A herbal tea without mint is an easy alternative.",
            sources: [.niddkEating],
            evidence: .mixedEvidence,
            lastReviewed: reviewedOn
        ),
        GERDRule(
            id: "rule.carbonated.v1",
            title: "Fizzy drinks",
            matchers: [.carbonated],
            explanation: "Fizzy drinks are sometimes linked with reflux symptoms.",
            suggestion: "Still water is an easy swap if you fancy it.",
            sources: [.acgAcidReflux],
            evidence: .mixedEvidence,
            lastReviewed: reviewedOn
        ),
        GERDRule(
            id: "rule.lateEvening.v1",
            title: "Late in the evening",
            matchers: [.lateEvening],
            explanation: "Eating shortly before lying down can make reflux more likely.",
            suggestion: "Staying upright for a couple of hours afterwards may help.",
            sources: [.niddkEating, .niddkSymptoms],
            evidence: .commonlyCited,
            lastReviewed: reviewedOn
        )
    ]

    /// Deliberately **not** a rule.
    ///
    /// `FoodCategory.dairy` on its own matches nothing. Mainstream guidance does
    /// not list dairy as something to avoid for reflux; what it lists is fat. So
    /// milk in tea changes nothing here, while `fullFatDairy` — cream, full-fat
    /// cheese, whole milk — is matched by `rule.highFat.v1` for the fat, not for
    /// being dairy. If an individual pattern shows up for this user it belongs
    /// in ``InsightEngine``, as an observation, not as a baseline rule.
    public static let intentionallyUnmatched: Set<FoodCategory> = [.dairy]
}
