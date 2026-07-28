import Foundation

public enum InsightKind: Sendable, Hashable {
    case category(FoodCategory)
    case eveningMeals
    case notEnoughInformation
}

public struct Insight: Sendable, Hashable, Identifiable {
    /// The one sentence about correlation that accompanies every observation.
    public static let correlationNote =
        "This shows what you recorded around the same time. It does not show that one led to the other."

    public let id: String
    public let headline: String
    public let detail: String
    /// How many recorded observations this is based on. Always shown.
    public let observationCount: Int
    public let symptomCount: Int
    /// The meals behind the number, so the user can look at them.
    public let mealIDs: [UUID]
    public let kind: InsightKind

    public var isActionable: Bool { kind != .notEnoughInformation }
}

/// Counts what was recorded. Nothing more.
///
/// The engine reports plain fractions over observations the user actually made,
/// never a rate, a score, or a claim about what any of it means. Anything below
/// the thresholds is reported as "not enough information yet" rather than
/// quietly omitted, so the user can tell the difference between "no pattern" and
/// "not looked at".
public struct InsightEngine: Sendable {
    /// Fewest observations of a category before it is worth mentioning at all.
    public static let minimumObservations = 3
    /// Fewest symptom reports before a category is worth mentioning.
    public static let minimumSymptomObservations = 2
    /// Below this sample size, percentages are misleading, so counts only.
    public static let percentageSampleThreshold = 10
    /// Meals at or after this hour count as "later in the day".
    public static let eveningHour = 19

    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func insights(from meals: [MealSnapshot]) -> [Insight] {
        let observed = meals.filter { $0.checkIn != nil }
        guard observed.count >= Self.minimumObservations else {
            return [notEnoughInformation(observationCount: observed.count)]
        }

        var found = categoryInsights(observed)
        if let evening = eveningInsight(observed) {
            found.append(evening)
        }

        guard !found.isEmpty else {
            return [notEnoughInformation(observationCount: observed.count)]
        }

        return found.sorted {
            if $0.symptomCount != $1.symptomCount { return $0.symptomCount > $1.symptomCount }
            if $0.observationCount != $1.observationCount { return $0.observationCount > $1.observationCount }
            return $0.id < $1.id
        }
    }

    /// A short line of personal history for the result screen.
    ///
    /// Context only — it never changes, softens or strengthens the baseline note
    /// from ``GERDRulesEngine``.
    public func personalNote(for categories: Set<FoodCategory>, meals: [MealSnapshot]) -> String? {
        let counts: [(FoodCategory, Int)] = categories.compactMap { category in
            let matching = meals.filter { $0.presentCategories.contains(category) && $0.checkIn != nil }
            let symptomatic = matching.filter { $0.checkIn?.severity.indicatesSymptoms == true }.count
            guard symptomatic >= Self.minimumSymptomObservations else { return nil }
            return (category, symptomatic)
        }

        guard let best = counts.max(by: { $0.1 < $1.1 }) else { return nil }
        return "You have recorded symptoms after \(best.0.displayName.lowercased()) \(times(best.1)) before."
    }

    // MARK: - Private

    private func categoryInsights(_ observed: [MealSnapshot]) -> [Insight] {
        FoodCategory.allCases.compactMap { category in
            let matching = observed.filter { $0.presentCategories.contains(category) }
            let symptomatic = matching.filter { $0.checkIn?.severity.indicatesSymptoms == true }

            guard matching.count >= Self.minimumObservations,
                  symptomatic.count >= Self.minimumSymptomObservations
            else { return nil }

            let headline = "You reported symptoms \(symptomatic.count) of the \(matching.count) "
                + "times you recorded \(category.displayName.lowercased())."

            return Insight(
                id: "insight.category.\(category.rawValue)",
                headline: headline,
                detail: detailLine(symptomCount: symptomatic.count, observationCount: matching.count),
                observationCount: matching.count,
                symptomCount: symptomatic.count,
                mealIDs: matching.map(\.id),
                kind: .category(category)
            )
        }
    }

    private func eveningInsight(_ observed: [MealSnapshot]) -> Insight? {
        let later = observed.filter { calendar.component(.hour, from: $0.consumedAt) >= Self.eveningHour }
        let earlier = observed.filter { calendar.component(.hour, from: $0.consumedAt) < Self.eveningHour }

        guard later.count >= Self.minimumObservations, earlier.count >= Self.minimumObservations else {
            return nil
        }

        let laterSymptomatic = later.filter { $0.checkIn?.severity.indicatesSymptoms == true }.count
        let earlierSymptomatic = earlier.filter { $0.checkIn?.severity.indicatesSymptoms == true }.count
        guard laterSymptomatic >= Self.minimumSymptomObservations else { return nil }

        // Compare fractions without turning them into a rate on screen.
        let laterIsHigher = laterSymptomatic * earlier.count > earlierSymptomatic * later.count
        guard laterIsHigher else { return nil }

        let headline = "Symptoms were more common after later meals."
        let detail = "\(laterSymptomatic) of \(later.count) meals after "
            + "\(Self.eveningHour):00, compared with \(earlierSymptomatic) of \(earlier.count) earlier in the day. "
            + Insight.correlationNote

        return Insight(
            id: "insight.eveningMeals",
            headline: headline,
            detail: detail,
            observationCount: later.count + earlier.count,
            symptomCount: laterSymptomatic,
            mealIDs: later.map(\.id),
            kind: .eveningMeals
        )
    }

    private func detailLine(symptomCount: Int, observationCount: Int) -> String {
        guard observationCount >= Self.percentageSampleThreshold else {
            return "Based on \(observationCount) recorded observations. " + Insight.correlationNote
        }
        let percent = Int((Double(symptomCount) / Double(observationCount) * 100).rounded())
        return "Based on \(observationCount) recorded observations — about \(percent)%. "
            + Insight.correlationNote
    }

    private func notEnoughInformation(observationCount: Int) -> Insight {
        Insight(
            id: "insight.notEnoughInformation",
            headline: "There is not enough information yet to see a pattern.",
            detail: "So far you have recorded \(observationCount) "
                + "\(observationCount == 1 ? "meal" : "meals") with an answer afterwards. "
                + "A few more will make this more useful.",
            observationCount: observationCount,
            symptomCount: 0,
            mealIDs: [],
            kind: .notEnoughInformation
        )
    }

    private func times(_ count: Int) -> String {
        switch count {
        case 1: "once"
        case 2: "twice"
        default: "\(count) times"
        }
    }
}
