import Foundation

/// Chooses which questions — if any — to ask after a capture.
///
/// The hard cap of two is the product promise: a normal log is a photo and at
/// most two taps. Questions are only asked when the answer would change what is
/// shown, which is decided by ``GERDRulesEngine`` rather than by the recogniser.
public enum ClarificationPlanner {
    public static let maxQuestions = RecognitionLimits.maxClarificationQuestions

    public static func questions(
        response: RecognitionResponse?,
        evaluation: GERDEvaluation
    ) -> [ClarificationQuestion] {
        let materialCategories = evaluation.unconfirmedMaterialFacts.map(\.category)
        guard !materialCategories.isEmpty else { return [] }

        let proposed = response?.clarifications ?? []
        var chosen: [ClarificationQuestion] = []
        var covered: Set<FoodCategory> = []

        // Prefer the recogniser's own phrasing when it is about something that
        // actually matters — it can be more specific ("Was the tea caffeinated?").
        for question in proposed where materialCategories.contains(question.category) {
            guard !covered.contains(question.category) else { continue }
            chosen.append(question)
            covered.insert(question.category)
            if chosen.count == maxQuestions { return chosen }
        }

        // Fall back to our own wording for anything still unconfirmed.
        for fact in evaluation.unconfirmedMaterialFacts where !covered.contains(fact.category) {
            chosen.append(
                ClarificationQuestion(
                    id: "clarify.\(fact.category.rawValue)",
                    question: defaultQuestion(for: fact.category),
                    category: fact.category,
                    detail: fact.detail
                )
            )
            covered.insert(fact.category)
            if chosen.count == maxQuestions { return chosen }
        }

        return chosen
    }

    public static func defaultQuestion(for category: FoodCategory) -> String {
        switch category {
        case .caffeine: "Was this caffeinated?"
        case .chocolate: "Did this have chocolate in it?"
        case .alcohol: "Did this have alcohol in it?"
        case .mint: "Did this have mint in it?"
        case .tomato: "Did this have tomato in it?"
        case .citrus: "Did this have citrus in it?"
        case .spicy: "Was this spicy?"
        case .highFat: "Was this cooked with a lot of oil or butter?"
        case .fried: "Was this fried?"
        case .fullFatDairy: "Did this have cream or full-fat cheese in it?"
        case .dairy: "Did this have dairy in it?"
        case .carbonated: "Was this fizzy?"
        case .largePortion: "Was this a large portion?"
        case .lateEvening: "Was this eaten late in the evening?"
        }
    }
}
