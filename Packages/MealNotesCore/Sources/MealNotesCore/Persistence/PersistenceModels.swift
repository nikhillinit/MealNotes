import Foundation
import SwiftData

/// Stored meal.
///
/// Structured values (facts, corrections, provenance) are held as JSON blobs
/// rather than as SwiftData relationships. For a single-user journal this is a
/// deliberate trade: those values are always read together with their meal and
/// are never queried across, so relationships would add schema fragility for no
/// query benefit. Windows are joined by plain `windowID` for the same reason.
@Model
public final class MealRecord {
    public var id: UUID
    public var consumedAt: Date
    public var displayName: String
    public var factsJSON: Data
    public var correctionsJSON: Data
    public var provenanceJSON: Data
    /// Rules whose notes were on screen when the user confirmed the meal.
    public var shownRuleIDs: [String]
    public var windowID: UUID?
    /// Only ever non-nil when the user explicitly asked to keep the photo.
    @Attribute(.externalStorage) public var retainedPhotoData: Data?

    public init(
        id: UUID,
        consumedAt: Date,
        displayName: String,
        factsJSON: Data,
        correctionsJSON: Data,
        provenanceJSON: Data,
        shownRuleIDs: [String],
        windowID: UUID?,
        retainedPhotoData: Data?
    ) {
        self.id = id
        self.consumedAt = consumedAt
        self.displayName = displayName
        self.factsJSON = factsJSON
        self.correctionsJSON = correctionsJSON
        self.provenanceJSON = provenanceJSON
        self.shownRuleIDs = shownRuleIDs
        self.windowID = windowID
        self.retainedPhotoData = retainedPhotoData
    }
}

/// One eating window plus the single check-in that covers it.
@Model
public final class CheckInWindowRecord {
    public var id: UUID
    public var windowStart: Date
    public var latestMealAt: Date
    public var scheduledFireDate: Date
    public var notificationID: String
    public var respondedAt: Date?
    public var severityRaw: String?
    public var symptomsRaw: [String]
    public var urgentSymptomsRaw: [String]

    public init(
        id: UUID,
        windowStart: Date,
        latestMealAt: Date,
        scheduledFireDate: Date,
        notificationID: String,
        respondedAt: Date? = nil,
        severityRaw: String? = nil,
        symptomsRaw: [String] = [],
        urgentSymptomsRaw: [String] = []
    ) {
        self.id = id
        self.windowStart = windowStart
        self.latestMealAt = latestMealAt
        self.scheduledFireDate = scheduledFireDate
        self.notificationID = notificationID
        self.respondedAt = respondedAt
        self.severityRaw = severityRaw
        self.symptomsRaw = symptomsRaw
        self.urgentSymptomsRaw = urgentSymptomsRaw
    }

    public var response: CheckInSnapshot? {
        guard let respondedAt, let severityRaw, let severity = CheckInSeverity(rawValue: severityRaw) else {
            return nil
        }
        return CheckInSnapshot(
            respondedAt: respondedAt,
            severity: severity,
            symptoms: symptomsRaw.compactMap(SymptomTag.init(rawValue:)),
            urgentSymptoms: urgentSymptomsRaw.compactMap(UrgentSymptom.init(rawValue:))
        )
    }
}

/// The models that make up the app's store, in one place so the app, the tests
/// and the previews cannot drift apart.
public enum MealNotesSchema {
    public static let models: [any PersistentModel.Type] = [
        MealRecord.self,
        CheckInWindowRecord.self
    ]

    @MainActor
    public static func inMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: MealRecord.self, CheckInWindowRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @MainActor
    public static func onDiskContainer() throws -> ModelContainer {
        try ModelContainer(for: MealRecord.self, CheckInWindowRecord.self)
    }
}

/// JSON coding for the value types stored inside a `MealRecord`.
///
/// Encoders are made per call: `JSONEncoder` is not `Sendable`, and a shared
/// instance would be a data race waiting to happen.
enum RecordCodec {
    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, fallback: T) -> T {
        (try? JSONDecoder().decode(type, from: data)) ?? fallback
    }
}
