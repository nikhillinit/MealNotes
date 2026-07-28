import Foundation

/// How the user felt after an eating window.
public enum CheckInSeverity: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case fine
    case mild
    case moderate
    case severe

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fine: "Fine"
        case .mild: "Mild"
        case .moderate: "Moderate"
        case .severe: "Severe"
        }
    }

    /// Anything other than `fine` counts as "reported symptoms" for insights.
    public var indicatesSymptoms: Bool { self != .fine }

    /// A shape as well as a colour, so concern is never carried by colour alone.
    public var symbolName: String {
        switch self {
        case .fine: "checkmark.circle"
        case .mild: "circle.righthalf.filled"
        case .moderate: "exclamationmark.circle"
        case .severe: "exclamationmark.triangle"
        }
    }
}

/// Optional, fast symptom tagging offered after a non-`fine` answer.
public enum SymptomTag: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case heartburn
    case bloating
    case nausea
    case stomachPain
    case bowelChanges
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .heartburn: "Heartburn or reflux"
        case .bloating: "Bloating"
        case .nausea: "Nausea"
        case .stomachPain: "Stomach pain"
        case .bowelChanges: "Bowel changes"
        case .other: "Other"
        }
    }
}

/// Symptoms that should send the user to a clinician rather than to an insight.
///
/// Recording one of these shows a plain recommendation to seek care. The app does
/// not attempt to work out why the symptom happened or how urgent it is.
public enum UrgentSymptom: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case chestPain
    case difficultySwallowing
    case painWhenSwallowing
    case vomitingBlood
    case blackOrBloodyStool
    case persistentVomiting
    case unexplainedWeightLoss

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .chestPain: "Chest pain"
        case .difficultySwallowing: "Difficulty swallowing"
        case .painWhenSwallowing: "Pain when swallowing"
        case .vomitingBlood: "Vomiting blood"
        case .blackOrBloodyStool: "Black or bloody stool"
        case .persistentVomiting: "Vomiting that will not stop"
        case .unexplainedWeightLoss: "Weight loss you cannot explain"
        }
    }
}

/// A user's recorded answer to one check-in.
public struct CheckInSnapshot: Codable, Sendable, Hashable {
    public let respondedAt: Date
    public let severity: CheckInSeverity
    public let symptoms: [SymptomTag]
    public let urgentSymptoms: [UrgentSymptom]

    public init(
        respondedAt: Date,
        severity: CheckInSeverity,
        symptoms: [SymptomTag] = [],
        urgentSymptoms: [UrgentSymptom] = []
    ) {
        self.respondedAt = respondedAt
        self.severity = severity
        self.symptoms = symptoms
        self.urgentSymptoms = urgentSymptoms
    }
}
