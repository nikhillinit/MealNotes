import Foundation

public struct SafetyViolation: Sendable, Hashable, CustomStringConvertible {
    public let context: String
    public let phrase: String
    public let text: String

    public var description: String {
        "\(context) uses banned wording “\(phrase)”: \(text)"
    }
}

/// The wording guardrail for anything the app says about food.
///
/// This is a real check, not documentation: `SafetyWordingTests` runs it over
/// every rule and every insight string, so the copy cannot drift into claiming
/// that a food is one thing or another, or that it will do something.
///
/// Scope note: the check applies to rule and insight copy — the places where the
/// app talks about food. It deliberately does **not** apply to
/// ``AppDisclosures`` or ``UrgentCarePolicy``, which have to use words like
/// "medical care" and "should" to be clear about seeking help.
public enum SafetyWording {
    /// Labels the app must not apply to a food, and claims it must not make.
    public static let bannedPhrases: [String] = [
        // Labelling a food.
        "safe", "unsafe", "healthy", "unhealthy", "good", "bad",
        // Claiming certainty.
        "guarantee", "guaranteed", "proven", "proof",
        "always", "never", "definitely", "certainly",
        // Claiming causation.
        "cause", "causes", "caused", "causing",
        // Medical claims.
        "diagnose", "diagnosis", "diagnostic", "cure", "treat", "treatment",
        "allergy", "allergic", "intolerance", "intolerant",
        // Alarming or absolute framing.
        "trigger", "triggers", "toxic", "poison", "dangerous", "harmful", "must"
    ]

    /// Finds banned phrases using whole-word matching, so "safety" does not trip
    /// on "safe" and "treatment" is caught on its own terms.
    public static func violations(in text: String, context: String) -> [SafetyViolation] {
        let words = tokenize(text)
        guard !words.isEmpty else { return [] }

        return bannedPhrases.compactMap { phrase in
            let phraseWords = tokenize(phrase)
            guard !phraseWords.isEmpty, contains(words, phraseWords) else { return nil }
            return SafetyViolation(context: context, phrase: phrase, text: text)
        }
    }

    /// Pseudo-precise risk framing: a percentage, or an explicit "risk score".
    public static func containsRiskScore(_ text: String) -> Bool {
        if text.contains("%") { return true }
        let lowered = text.lowercased()
        return lowered.contains("risk score") || lowered.contains("risk level")
    }

    /// Audits the wording a rule puts on screen. Source titles are excluded —
    /// they are citations and must be reproduced verbatim.
    public static func audit(_ rule: GERDRule) -> [SafetyViolation] {
        let fields: [(String, String)] = [
            ("\(rule.id).title", rule.title),
            ("\(rule.id).explanation", rule.explanation),
            ("\(rule.id).suggestion", rule.suggestion)
        ]
        return fields.flatMap { violations(in: $0.1, context: $0.0) }
    }

    public static func audit(_ rules: [GERDRule]) -> [SafetyViolation] {
        rules.flatMap(audit)
    }

    private static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    /// Contiguous-subsequence match, so multi-word phrases are matched as phrases.
    private static func contains(_ haystack: [String], _ needle: [String]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle { return true }
        }
        return false
    }
}

/// Fixed copy about what this app is and is not.
public enum AppDisclosures {
    public static let appName = "Meal Notes"

    public static let notMedicalCare = """
        Meal Notes is a private notebook, not medical care. It records what you \
        ate and how you felt afterwards, so you have something clear to look back \
        on and to show a doctor if you want to.

        It cannot examine you, and it does not know your history. Nothing here \
        replaces advice from a doctor or pharmacist.
        """

    public static let howWarningsWork = """
        The notes you see come from a small, fixed list of suggestions published \
        for people with reflux, by the National Institute of Diabetes and \
        Digestive and Kidney Diseases and the American College of \
        Gastroenterology. Each note shows where it came from.

        A note appears only when something was confirmed — by you, by a label, or \
        by a barcode — or when the photo was clear enough to be sure. When the app \
        is unsure, it asks you rather than guessing.
        """

    public static let privacySummary = """
        Everything stays on this iPhone. There is no account and no sign-in.

        Photos are used to work out what the food is and are then discarded, \
        unless you choose to keep one. Your meal history and how you felt are \
        never sent anywhere.
        """

    public static let whenToSeekHelp = """
        Some symptoms are worth having looked at promptly rather than tracked: \
        chest pain, trouble or pain when swallowing, vomiting blood, black or \
        bloody stools, vomiting that will not stop, or losing weight without \
        meaning to.

        If you record any of these, the app will say so. It cannot tell you how \
        serious something is — please contact a doctor.
        """
}
