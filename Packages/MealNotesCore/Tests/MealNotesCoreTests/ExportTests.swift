import Foundation
import Testing
@testable import MealNotesCore

@Suite("Report export")
struct ExportTests {
    let generatedAt = TestDates.at(18, 30)

    private var sampleMeals: [MealSnapshot] {
        [
            .stub(
                at: TestDates.at(8, 15),
                name: "Black tea",
                categories: [.caffeine],
                shownRuleIDs: ["rule.caffeine.v1"],
                corrections: [
                    MealCorrection(
                        createdAt: TestDates.at(8, 16),
                        field: .name,
                        previousValue: "Tea",
                        newValue: "Black tea"
                    )
                ],
                severity: .mild,
                symptoms: [.heartburn]
            ),
            .stub(
                at: TestDates.at(13, 0),
                name: "Salmon with couscous",
                categories: [],
                severity: .fine
            ),
            .stub(
                at: TestDates.at(20, 0),
                name: #"Pasta, "extra" spicy"#,
                categories: [.tomato, .spicy],
                shownRuleIDs: ["rule.acidicFoods.v1", "rule.spicy.v1"],
                severity: .severe,
                symptoms: [.stomachPain],
                urgentSymptoms: [.chestPain]
            )
        ]
    }

    // MARK: - Plain text

    @Test("The readable report carries everything a doctor would need")
    func plainTextContents() {
        let document = PlainTextReportExporter(timeZone: TestDates.timeZone)
            .export(meals: sampleMeals, generatedAt: generatedAt)
        let text = document.text

        // Date and time.
        #expect(text.contains("2026-03-10 08:15"))
        #expect(text.contains("2026-03-10 13:00"))
        // Confirmed names.
        #expect(text.contains("Black tea"))
        #expect(text.contains("Salmon with couscous"))
        // Confirmed categories.
        #expect(text.contains("Confirmed: Caffeine"))
        #expect(text.contains("Confirmed: Spicy, Tomato"))
        #expect(text.contains("Confirmed: nothing recorded"))
        // The note that was shown at the time, with its rule identifier.
        #expect(text.contains("Note shown: Caffeine — Caffeine can make reflux symptoms worse for some people."))
        #expect(text.contains("rule.caffeine.v1"))
        #expect(text.contains("Note shown: none"))
        // Check-in answers and symptoms.
        #expect(text.contains("How you felt: Mild — Heartburn or reflux"))
        #expect(text.contains("How you felt: Fine"))
        #expect(text.contains("also recorded: Chest pain"))
        // Corrections.
        #expect(text.contains(#"Name: “Tea” → “Black tea”"#))
    }

    @Test("The report says what it is, and cites its guidance")
    func plainTextFraming() {
        let text = PlainTextReportExporter(timeZone: TestDates.timeZone)
            .export(meals: sampleMeals, generatedAt: generatedAt).text

        #expect(text.contains("not medical care"))
        #expect(text.contains("not a diagnosis"))
        #expect(text.contains("3 entries recorded."))
        #expect(text.contains("https://www.niddk.nih.gov"))
        #expect(text.contains("https://gi.org/topics/acid-reflux/"))
    }

    @Test("Entries are ordered oldest first and the file is named for the day")
    func plainTextOrdering() throws {
        let document = PlainTextReportExporter(timeZone: TestDates.timeZone)
            .export(meals: sampleMeals.reversed(), generatedAt: generatedAt)

        #expect(document.filename == "MealNotes-2026-03-10.txt")
        #expect(document.format == .plainText)

        let tea = try #require(document.text.range(of: "Black tea"))
        let pasta = try #require(document.text.range(of: "Pasta,"))
        #expect(tea.lowerBound < pasta.lowerBound)
    }

    @Test("An empty history still produces a valid report")
    func emptyReport() {
        let document = PlainTextReportExporter(timeZone: TestDates.timeZone)
            .export(meals: [], generatedAt: generatedAt)

        #expect(document.text.contains("0 entries recorded."))
        #expect(document.data.isEmpty == false)
    }

    // MARK: - CSV

    @Test("The CSV has one header row and one row per meal")
    func csvShape() throws {
        let document = CSVReportExporter(timeZone: TestDates.timeZone)
            .export(meals: sampleMeals, generatedAt: generatedAt)
        let rows = document.text.split(separator: "\n", omittingEmptySubsequences: false)

        #expect(document.filename == "MealNotes-2026-03-10.csv")
        #expect(rows.count == sampleMeals.count + 1)
        #expect(rows[0] == CSVReportExporter.columns.joined(separator: ","))
        #expect(rows[1].hasPrefix(#""2026-03-10","08:15","Black tea""#))
    }

    @Test("Quotes and commas in a name are escaped, not lost")
    func csvEscaping() throws {
        let document = CSVReportExporter(timeZone: TestDates.timeZone)
            .export(meals: sampleMeals, generatedAt: generatedAt)
        let pastaRow = try #require(document.text.split(separator: "\n").last)

        #expect(pastaRow.contains(#""Pasta, ""extra"" spicy""#))
        #expect(pastaRow.contains(#""Spicy; Tomato""#))
        #expect(pastaRow.contains(#""Severe""#))
        #expect(pastaRow.contains(#""Chest pain""#))
        #expect(pastaRow.contains("rule.acidicFoods.v1 | rule.spicy.v1"))
    }

    @Test("Both formats cover every field the brief asks for")
    func coversRequiredFields() {
        let expected = [
            "date", "time", "item", "confirmed_categories",
            "notes_shown", "check_in", "symptoms", "corrections"
        ]
        for column in expected {
            #expect(CSVReportExporter.columns.contains(column), "missing column \(column)")
        }
    }

    @Test("A hand-typed meal is labelled as such")
    func manualEntryProvenance() {
        let manual = MealSnapshot.stub(
            at: TestDates.at(9),
            name: "Porridge",
            severity: .fine,
            provenance: .manualEntry
        )
        let text = PlainTextReportExporter(timeZone: TestDates.timeZone)
            .export(meals: [manual], generatedAt: generatedAt).text

        #expect(text.contains("Identified by: Typed by hand"))
    }
}

@Suite("Urgent symptoms")
struct UrgentCarePolicyTests {
    @Test("Ordinary symptoms produce no advisory")
    func noAdvisory() {
        #expect(UrgentCarePolicy.advisory(for: []) == nil)
    }

    @Test("Any listed symptom produces the recommendation", arguments: UrgentSymptom.allCases)
    func everySymptomIsCovered(symptom: UrgentSymptom) throws {
        let advisory = try #require(UrgentCarePolicy.advisory(for: [symptom]))

        #expect(advisory.title == "Please speak to a doctor")
        #expect(advisory.message.contains(symptom.displayName.lowercased()))
        #expect(advisory.symptoms == [symptom])
    }

    @Test("Several symptoms are listed in a fixed order")
    func stableOrdering() throws {
        let advisory = try #require(
            UrgentCarePolicy.advisory(for: [.unexplainedWeightLoss, .chestPain, .vomitingBlood])
        )
        #expect(advisory.symptoms == [.chestPain, .vomitingBlood, .unexplainedWeightLoss])
        #expect(advisory.message.contains("chest pain, vomiting blood, and weight loss you cannot explain"))
    }

    @Test("The recommendation defers rather than triaging or explaining")
    func defersToClinicians() throws {
        let advisory = try #require(UrgentCarePolicy.advisory(for: [.chestPain]))
        let message = advisory.message.lowercased()

        #expect(message.contains("cannot tell how serious"))
        #expect(message.contains("emergency services"))
        // No attempt to say what it is or how likely anything is.
        #expect(message.contains("probably") == false)
        #expect(message.contains("likely") == false)
        #expect(message.contains("reflux") == false)
        #expect(SafetyWording.containsRiskScore(advisory.message) == false)
    }
}
