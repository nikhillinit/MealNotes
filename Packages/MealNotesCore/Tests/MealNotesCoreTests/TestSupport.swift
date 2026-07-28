import Foundation
@testable import MealNotesCore

enum TestDates {
    /// All test dates are built in UTC so hour-of-day behaviour (late evening,
    /// evening insights) is stable wherever the tests run.
    static let calendar = CalendarSupport.utc
    static let timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

    static func at(_ hour: Int, _ minute: Int = 0, day: Int = 10) -> Date {
        CalendarSupport.date(2026, 3, day, hour, minute)
    }
}

extension MealSnapshot {
    static func stub(
        id: UUID = UUID(),
        at date: Date,
        name: String = "Test meal",
        categories: [FoodCategory] = [],
        shownRuleIDs: [String] = [],
        corrections: [MealCorrection] = [],
        severity: CheckInSeverity? = nil,
        symptoms: [SymptomTag] = [],
        urgentSymptoms: [UrgentSymptom] = [],
        provenance: RecognitionProvenance = RecognitionProvenance(proposedName: "Test meal", overallConfidence: 0.9)
    ) -> MealSnapshot {
        MealSnapshot(
            id: id,
            consumedAt: date,
            displayName: name,
            facts: categories.map { FoodFact.confirmed($0, isPresent: true) },
            shownRuleIDs: shownRuleIDs,
            corrections: corrections,
            provenance: provenance,
            windowID: nil,
            checkIn: severity.map {
                CheckInSnapshot(
                    respondedAt: date.addingTimeInterval(7200),
                    severity: $0,
                    symptoms: symptoms,
                    urgentSymptoms: urgentSymptoms
                )
            }
        )
    }
}

extension MealDraft {
    static func stub(
        at date: Date,
        name: String = "Test meal",
        facts: [FoodFact] = [],
        shownRuleIDs: [String] = []
    ) -> MealDraft {
        MealDraft(
            consumedAt: date,
            displayName: name,
            facts: facts,
            shownRuleIDs: shownRuleIDs,
            provenance: RecognitionProvenance(proposedName: name, overallConfidence: 0.9)
        )
    }
}
