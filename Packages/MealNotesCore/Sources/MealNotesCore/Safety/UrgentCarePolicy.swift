import Foundation

public struct UrgentAdvisory: Sendable, Hashable {
    public let title: String
    public let message: String
    public let symptoms: [UrgentSymptom]
}

/// Decides when to recommend seeking care instead of carrying on journalling.
///
/// The policy is deliberately blunt: any one of these symptoms produces the same
/// recommendation. The app does not rank them, does not estimate urgency, and
/// does not suggest what might be behind them.
public enum UrgentCarePolicy {
    public static func advisory(for symptoms: [UrgentSymptom]) -> UrgentAdvisory? {
        guard !symptoms.isEmpty else { return nil }

        // Preserve the canonical order rather than the order they were tapped.
        let ordered = UrgentSymptom.allCases.filter(symptoms.contains)
        let names = ordered.map { $0.displayName.lowercased() }

        return UrgentAdvisory(
            title: "Please speak to a doctor",
            message: """
                You recorded \(list(names)). That is worth having checked promptly \
                rather than only written down here.

                This app cannot tell how serious it is. If you are worried, or it \
                feels like an emergency, contact your doctor or emergency services now.
                """,
            symptoms: ordered
        )
    }

    private static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: "\(items.dropLast().joined(separator: ", ")), and \(items[items.count - 1])"
        }
    }
}
