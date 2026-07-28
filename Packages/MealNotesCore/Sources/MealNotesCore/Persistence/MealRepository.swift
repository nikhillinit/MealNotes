import Foundation
import SwiftData

public enum RepositoryError: Error, Sendable, Equatable {
    case windowNotFound(UUID)
    case mealNotFound(UUID)
}

public enum CheckInPolicy {
    /// How long an unanswered check-in keeps showing in the app.
    public static let pendingLifetime: TimeInterval = 24 * 60 * 60
}

/// Storage for meals and their check-ins.
///
/// Main-actor bound because SwiftData's `ModelContext` is not `Sendable`. Pure
/// logic (rules, insights, export) works on `MealSnapshot` instead, so none of
/// it inherits this constraint.
@MainActor
public protocol MealRepository: AnyObject {
    @discardableResult
    func save(_ draft: MealDraft, windowID: UUID?) throws -> MealSnapshot

    func meal(id: UUID) throws -> MealSnapshot?
    func meals(withIDs ids: [UUID]) throws -> [MealSnapshot]
    func recentMeals(limit: Int) throws -> [MealSnapshot]
    func allMeals() throws -> [MealSnapshot]

    /// Applies a correction and records what changed.
    @discardableResult
    func applyCorrection(
        mealID: UUID,
        newDisplayName: String?,
        newFacts: [FoodFact]?,
        at date: Date
    ) throws -> MealSnapshot

    func openWindows(asOf now: Date) throws -> [CheckInWindowSnapshot]
    func dueWindows(asOf now: Date) throws -> [CheckInWindowSnapshot]
    func window(id: UUID) throws -> CheckInWindowSnapshot?
    func createWindow(id: UUID, mealAt: Date, fireDate: Date, notificationID: String) throws
    func extendWindow(id: UUID, latestMealAt: Date, fireDate: Date) throws
    func recordCheckIn(windowID: UUID, response: CheckInSnapshot) throws

    func deleteAllData() throws
}

@MainActor
public final class SwiftDataMealRepository: MealRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public convenience init(container: ModelContainer) {
        self.init(context: ModelContext(container))
    }

    // MARK: - Meals

    @discardableResult
    public func save(_ draft: MealDraft, windowID: UUID?) throws -> MealSnapshot {
        let record = MealRecord(
            id: draft.id,
            consumedAt: draft.consumedAt,
            displayName: draft.displayName,
            factsJSON: RecordCodec.encode(draft.facts),
            correctionsJSON: RecordCodec.encode(draft.corrections),
            provenanceJSON: RecordCodec.encode(draft.provenance),
            shownRuleIDs: draft.shownRuleIDs,
            windowID: windowID,
            // Photos are discarded after recognition unless the user asked to
            // keep this one; `retainedPhotoData` is nil in every other case.
            retainedPhotoData: draft.retainedPhotoData
        )
        context.insert(record)
        try context.save()
        return try snapshot(record)
    }

    public func meal(id: UUID) throws -> MealSnapshot? {
        guard let record = try record(id: id) else { return nil }
        return try snapshot(record)
    }

    public func meals(withIDs ids: [UUID]) throws -> [MealSnapshot] {
        let wanted = Set(ids)
        return try allMeals().filter { wanted.contains($0.id) }
    }

    public func recentMeals(limit: Int) throws -> [MealSnapshot] {
        var descriptor = FetchDescriptor<MealRecord>(
            sortBy: [SortDescriptor(\.consumedAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(0, limit)
        return try snapshots(context.fetch(descriptor))
    }

    public func allMeals() throws -> [MealSnapshot] {
        let descriptor = FetchDescriptor<MealRecord>(
            sortBy: [SortDescriptor(\.consumedAt, order: .reverse)]
        )
        return try snapshots(context.fetch(descriptor))
    }

    @discardableResult
    public func applyCorrection(
        mealID: UUID,
        newDisplayName: String?,
        newFacts: [FoodFact]?,
        at date: Date
    ) throws -> MealSnapshot {
        guard let record = try record(id: mealID) else {
            throw RepositoryError.mealNotFound(mealID)
        }

        var corrections = RecordCodec.decode([MealCorrection].self, from: record.correctionsJSON, fallback: [])

        if let newDisplayName, newDisplayName != record.displayName {
            corrections.append(
                MealCorrection(
                    createdAt: date,
                    field: .name,
                    previousValue: record.displayName,
                    newValue: newDisplayName
                )
            )
            record.displayName = newDisplayName
        }

        if let newFacts {
            let existing = RecordCodec.decode([FoodFact].self, from: record.factsJSON, fallback: [])
            let resolved = FactResolver.resolve(newFacts)
            if Set(existing) != Set(resolved) {
                corrections.append(
                    MealCorrection(
                        createdAt: date,
                        field: .ingredients,
                        previousValue: Self.describe(existing),
                        newValue: Self.describe(resolved)
                    )
                )
                record.factsJSON = RecordCodec.encode(resolved)
            }
        }

        record.correctionsJSON = RecordCodec.encode(corrections)
        try context.save()
        return try snapshot(record)
    }

    // MARK: - Windows

    public func openWindows(asOf now: Date) throws -> [CheckInWindowSnapshot] {
        try windowSnapshots()
            .filter { !$0.isAnswered }
            .filter { abs(now.timeIntervalSince($0.latestMealAt)) <= CheckInPolicy.pendingLifetime }
    }

    public func dueWindows(asOf now: Date) throws -> [CheckInWindowSnapshot] {
        try windowSnapshots()
            .filter { $0.isDue(at: now) }
            .filter { now.timeIntervalSince($0.scheduledFireDate) <= CheckInPolicy.pendingLifetime }
            .sorted { $0.scheduledFireDate > $1.scheduledFireDate }
    }

    public func window(id: UUID) throws -> CheckInWindowSnapshot? {
        try windowSnapshots().first { $0.id == id }
    }

    public func createWindow(id: UUID, mealAt: Date, fireDate: Date, notificationID: String) throws {
        let record = CheckInWindowRecord(
            id: id,
            windowStart: mealAt,
            latestMealAt: mealAt,
            scheduledFireDate: fireDate,
            notificationID: notificationID
        )
        context.insert(record)
        try context.save()
    }

    public func extendWindow(id: UUID, latestMealAt: Date, fireDate: Date) throws {
        guard let record = try windowRecord(id: id) else {
            throw RepositoryError.windowNotFound(id)
        }
        record.latestMealAt = max(record.latestMealAt, latestMealAt)
        record.windowStart = min(record.windowStart, latestMealAt)
        record.scheduledFireDate = fireDate
        try context.save()
    }

    public func recordCheckIn(windowID: UUID, response: CheckInSnapshot) throws {
        guard let record = try windowRecord(id: windowID) else {
            throw RepositoryError.windowNotFound(windowID)
        }
        record.respondedAt = response.respondedAt
        record.severityRaw = response.severity.rawValue
        record.symptomsRaw = response.symptoms.map(\.rawValue)
        record.urgentSymptomsRaw = response.urgentSymptoms.map(\.rawValue)
        try context.save()
    }

    public func deleteAllData() throws {
        try context.delete(model: MealRecord.self)
        try context.delete(model: CheckInWindowRecord.self)
        try context.save()
    }

    // MARK: - Mapping

    private func record(id: UUID) throws -> MealRecord? {
        let descriptor = FetchDescriptor<MealRecord>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    private func windowRecord(id: UUID) throws -> CheckInWindowRecord? {
        let descriptor = FetchDescriptor<CheckInWindowRecord>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    private func windowSnapshots() throws -> [CheckInWindowSnapshot] {
        let windows = try context.fetch(FetchDescriptor<CheckInWindowRecord>())
        let meals = try context.fetch(FetchDescriptor<MealRecord>())
        let mealsByWindow = Dictionary(grouping: meals.filter { $0.windowID != nil }) { $0.windowID! }

        return windows.map { window in
            CheckInWindowSnapshot(
                id: window.id,
                windowStart: window.windowStart,
                latestMealAt: window.latestMealAt,
                scheduledFireDate: window.scheduledFireDate,
                notificationID: window.notificationID,
                mealIDs: (mealsByWindow[window.id] ?? [])
                    .sorted { $0.consumedAt < $1.consumedAt }
                    .map(\.id),
                response: window.response
            )
        }
    }

    private func snapshots(_ records: [MealRecord]) throws -> [MealSnapshot] {
        let responses = try windowResponsesByID()
        return records.map { snapshot($0, responses: responses) }
    }

    private func snapshot(_ record: MealRecord) throws -> MealSnapshot {
        snapshot(record, responses: try windowResponsesByID())
    }

    private func windowResponsesByID() throws -> [UUID: CheckInSnapshot] {
        let windows = try context.fetch(FetchDescriptor<CheckInWindowRecord>())
        return windows.reduce(into: [:]) { result, window in
            if let response = window.response { result[window.id] = response }
        }
    }

    private func snapshot(_ record: MealRecord, responses: [UUID: CheckInSnapshot]) -> MealSnapshot {
        MealSnapshot(
            id: record.id,
            consumedAt: record.consumedAt,
            displayName: record.displayName,
            facts: RecordCodec.decode([FoodFact].self, from: record.factsJSON, fallback: []),
            shownRuleIDs: record.shownRuleIDs,
            corrections: RecordCodec.decode([MealCorrection].self, from: record.correctionsJSON, fallback: []),
            provenance: RecordCodec.decode(
                RecognitionProvenance.self,
                from: record.provenanceJSON,
                fallback: .manualEntry
            ),
            windowID: record.windowID,
            checkIn: record.windowID.flatMap { responses[$0] },
            retainedPhoto: record.retainedPhotoData != nil
        )
    }

    private static func describe(_ facts: [FoodFact]) -> String {
        let present = facts.filter(\.isPresent).map(\.category.displayName).sorted()
        return present.isEmpty ? "none" : present.joined(separator: ", ")
    }
}
