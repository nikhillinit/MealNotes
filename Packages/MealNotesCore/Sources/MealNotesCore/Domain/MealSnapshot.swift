import Foundation

/// An edit the user made to a meal, kept so the exported report can show what
/// the app proposed and what the user actually said.
public struct MealCorrection: Codable, Sendable, Hashable, Identifiable {
    public enum Field: String, Codable, Sendable {
        case name
        case ingredients

        public var displayName: String {
            switch self {
            case .name: "Name"
            case .ingredients: "Ingredients"
            }
        }
    }

    public let id: UUID
    public let createdAt: Date
    public let field: Field
    public let previousValue: String
    public let newValue: String

    public init(id: UUID = UUID(), createdAt: Date, field: Field, previousValue: String, newValue: String) {
        self.id = id
        self.createdAt = createdAt
        self.field = field
        self.previousValue = previousValue
        self.newValue = newValue
    }
}

/// How the identification for a meal was arrived at.
public struct RecognitionProvenance: Codable, Sendable, Hashable {
    public let fixtureID: String?
    public let proposedName: String?
    public let overallConfidence: Double
    public let repairAttempted: Bool
    public let usedManualEntry: Bool
    public let limitations: [String]

    public init(
        fixtureID: String? = nil,
        proposedName: String? = nil,
        overallConfidence: Double = 0,
        repairAttempted: Bool = false,
        usedManualEntry: Bool = false,
        limitations: [String] = []
    ) {
        self.fixtureID = fixtureID
        self.proposedName = proposedName
        self.overallConfidence = min(max(overallConfidence, 0), 1)
        self.repairAttempted = repairAttempted
        self.usedManualEntry = usedManualEntry
        self.limitations = limitations
    }

    public static let manualEntry = RecognitionProvenance(usedManualEntry: true)
}

/// An immutable, `Sendable` view of one logged meal.
///
/// Everything downstream of persistence — insights, export, the rules engine —
/// works on snapshots rather than on SwiftData models, so those components stay
/// pure, testable and free of any storage or main-actor requirements.
public struct MealSnapshot: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let consumedAt: Date
    /// The name as the user confirmed it.
    public let displayName: String
    /// Resolved facts, i.e. after information precedence has been applied.
    public let facts: [FoodFact]
    /// Identifiers of the rules whose warnings were on screen when the user tapped
    /// "I'm having this". Recorded so the report can reproduce what was shown.
    public let shownRuleIDs: [String]
    public let corrections: [MealCorrection]
    public let provenance: RecognitionProvenance
    /// The eating window this meal was folded into, if any.
    public let windowID: UUID?
    public let checkIn: CheckInSnapshot?
    public let retainedPhoto: Bool

    public init(
        id: UUID,
        consumedAt: Date,
        displayName: String,
        facts: [FoodFact],
        shownRuleIDs: [String],
        corrections: [MealCorrection] = [],
        provenance: RecognitionProvenance,
        windowID: UUID? = nil,
        checkIn: CheckInSnapshot? = nil,
        retainedPhoto: Bool = false
    ) {
        self.id = id
        self.consumedAt = consumedAt
        self.displayName = displayName
        self.facts = facts
        self.shownRuleIDs = shownRuleIDs
        self.corrections = corrections
        self.provenance = provenance
        self.windowID = windowID
        self.checkIn = checkIn
        self.retainedPhoto = retainedPhoto
    }

    /// Categories that were asserted as present with enough trust to matter.
    public var presentCategories: Set<FoodCategory> {
        Set(facts.filter { $0.isPresent && $0.isStrongEnoughToWarn }.map(\.category))
    }
}

/// Everything needed to write one new meal to storage.
public struct MealDraft: Sendable, Hashable {
    public var id: UUID
    public var consumedAt: Date
    public var displayName: String
    public var facts: [FoodFact]
    public var shownRuleIDs: [String]
    public var corrections: [MealCorrection]
    public var provenance: RecognitionProvenance
    public var retainedPhotoData: Data?

    public init(
        id: UUID = UUID(),
        consumedAt: Date,
        displayName: String,
        facts: [FoodFact],
        shownRuleIDs: [String],
        corrections: [MealCorrection] = [],
        provenance: RecognitionProvenance,
        retainedPhotoData: Data? = nil
    ) {
        self.id = id
        self.consumedAt = consumedAt
        self.displayName = displayName
        self.facts = facts
        self.shownRuleIDs = shownRuleIDs
        self.corrections = corrections
        self.provenance = provenance
        self.retainedPhotoData = retainedPhotoData
    }
}
