import Foundation

public enum ExportFormat: String, Sendable, Hashable, CaseIterable, Identifiable {
    case plainText
    case csv

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .plainText: "Readable summary"
        case .csv: "Spreadsheet (CSV)"
        }
    }

    public var fileExtension: String {
        switch self {
        case .plainText: "txt"
        case .csv: "csv"
        }
    }

    public var utTypeIdentifier: String {
        switch self {
        case .plainText: "public.plain-text"
        case .csv: "public.comma-separated-values-text"
        }
    }
}

public struct ExportDocument: Sendable, Hashable {
    public let filename: String
    public let format: ExportFormat
    public let text: String

    public var data: Data { Data(text.utf8) }
}

/// Produces something the user can hand to a doctor from the share sheet.
public protocol ReportExporter: Sendable {
    var format: ExportFormat { get }
    func export(meals: [MealSnapshot], generatedAt: Date) -> ExportDocument
}

/// Stable, locale-independent formatting so an exported file reads the same
/// however the phone is configured, and so tests can assert on it.
struct ReportDateFormatting: Sendable {
    let timeZone: TimeZone

    private func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }

    func day(_ date: Date) -> String { formatter("yyyy-MM-dd").string(from: date) }
    func time(_ date: Date) -> String { formatter("HH:mm").string(from: date) }
    func dayAndTime(_ date: Date) -> String { formatter("yyyy-MM-dd HH:mm").string(from: date) }
}

/// Shared rendering of the parts both formats need.
struct ReportContent: Sendable {
    let rules: [GERDRule]

    func categories(_ meal: MealSnapshot) -> [String] {
        meal.facts
            .filter { $0.isPresent && $0.isStrongEnoughToWarn }
            .map(\.category.displayName)
            .sorted()
    }

    func rules(shownIn meal: MealSnapshot) -> [GERDRule] {
        meal.shownRuleIDs.compactMap { id in rules.first { $0.id == id } }
    }

    func checkInDescription(_ meal: MealSnapshot) -> String {
        guard let checkIn = meal.checkIn else { return "No answer recorded" }
        var parts = [checkIn.severity.displayName]
        if !checkIn.symptoms.isEmpty {
            parts.append(checkIn.symptoms.map(\.displayName).joined(separator: ", "))
        }
        if !checkIn.urgentSymptoms.isEmpty {
            parts.append("also recorded: " + checkIn.urgentSymptoms.map(\.displayName).joined(separator: ", "))
        }
        return parts.joined(separator: " — ")
    }

    func correctionDescriptions(_ meal: MealSnapshot) -> [String] {
        meal.corrections.map { correction in
            "\(correction.field.displayName): “\(correction.previousValue)” → “\(correction.newValue)”"
        }
    }

    func provenanceDescription(_ meal: MealSnapshot) -> String {
        if meal.provenance.usedManualEntry { return "Typed by hand" }
        let name = meal.provenance.proposedName ?? "—"
        let confidence = Int((meal.provenance.overallConfidence * 100).rounded())
        var text = "Suggested “\(name)” (confidence \(confidence)/100)"
        if meal.provenance.repairAttempted { text += ", after one retry" }
        return text
    }

    var uniqueSources: [RuleSource] {
        var seen: Set<URL> = []
        return rules.flatMap(\.sources).filter { seen.insert($0.url).inserted }
    }
}

public struct PlainTextReportExporter: ReportExporter {
    public let format = ExportFormat.plainText
    private let content: ReportContent
    private let dates: ReportDateFormatting

    public init(rules: [GERDRule] = GERDRuleCatalog.defaultRules, timeZone: TimeZone = .current) {
        self.content = ReportContent(rules: rules)
        self.dates = ReportDateFormatting(timeZone: timeZone)
    }

    public func export(meals: [MealSnapshot], generatedAt: Date) -> ExportDocument {
        let ordered = meals.sorted { $0.consumedAt < $1.consumedAt }
        var lines: [String] = []

        lines.append("\(AppDisclosures.appName) — food and symptom record")
        lines.append("Generated \(dates.dayAndTime(generatedAt))")
        lines.append("")
        lines.append(
            """
            This is a personal record kept on one iPhone. It is not medical care and \
            it is not a diagnosis. The notes shown at the time came from a fixed list \
            of published suggestions for people with reflux, listed at the end.
            """
        )
        lines.append("")
        lines.append("\(ordered.count) \(ordered.count == 1 ? "entry" : "entries") recorded.")
        lines.append("")

        for meal in ordered {
            lines.append(String(repeating: "─", count: 40))
            lines.append("\(dates.dayAndTime(meal.consumedAt)) — \(meal.displayName)")

            let categories = content.categories(meal)
            lines.append("Confirmed: \(categories.isEmpty ? "nothing recorded" : categories.joined(separator: ", "))")

            let shown = content.rules(shownIn: meal)
            if shown.isEmpty {
                lines.append("Note shown: none")
            } else {
                for rule in shown {
                    lines.append("Note shown: \(rule.title) — \(rule.explanation)")
                    lines.append("  Suggestion: \(rule.suggestion)")
                    lines.append("  Basis: \(rule.evidence.displayName)")
                    lines.append("  Rule: \(rule.id)")
                }
            }

            lines.append("How you felt: \(content.checkInDescription(meal))")

            let corrections = content.correctionDescriptions(meal)
            if !corrections.isEmpty {
                lines.append("You corrected: \(corrections.joined(separator: "; "))")
            }

            lines.append("Identified by: \(content.provenanceDescription(meal))")
            lines.append("")
        }

        lines.append(String(repeating: "─", count: 40))
        lines.append("Guidance the notes came from:")
        for source in content.uniqueSources {
            lines.append("• \(source.title) — \(source.url.absoluteString)")
        }

        return ExportDocument(
            filename: "MealNotes-\(dates.day(generatedAt)).txt",
            format: format,
            text: lines.joined(separator: "\n")
        )
    }
}

public struct CSVReportExporter: ReportExporter {
    public let format = ExportFormat.csv
    private let content: ReportContent
    private let dates: ReportDateFormatting

    public static let columns = [
        "date", "time", "item", "confirmed_categories", "notes_shown", "note_rule_ids",
        "check_in", "symptoms", "urgent_symptoms", "corrections", "identified_by"
    ]

    public init(rules: [GERDRule] = GERDRuleCatalog.defaultRules, timeZone: TimeZone = .current) {
        self.content = ReportContent(rules: rules)
        self.dates = ReportDateFormatting(timeZone: timeZone)
    }

    public func export(meals: [MealSnapshot], generatedAt: Date) -> ExportDocument {
        let ordered = meals.sorted { $0.consumedAt < $1.consumedAt }
        var rows: [String] = [Self.columns.joined(separator: ",")]

        for meal in ordered {
            let shown = content.rules(shownIn: meal)
            let checkIn = meal.checkIn

            let noteTexts: [String] = shown.map { rule in "\(rule.title): \(rule.explanation)" }
            let ruleIDs: [String] = shown.map(\.id)
            let symptoms: [String] = checkIn?.symptoms.map(\.displayName) ?? []
            let urgent: [String] = checkIn?.urgentSymptoms.map(\.displayName) ?? []

            var fields: [String] = []
            fields.append(dates.day(meal.consumedAt))
            fields.append(dates.time(meal.consumedAt))
            fields.append(meal.displayName)
            fields.append(content.categories(meal).joined(separator: "; "))
            fields.append(noteTexts.joined(separator: " | "))
            fields.append(ruleIDs.joined(separator: " | "))
            fields.append(checkIn?.severity.displayName ?? "")
            fields.append(symptoms.joined(separator: "; "))
            fields.append(urgent.joined(separator: "; "))
            fields.append(content.correctionDescriptions(meal).joined(separator: " | "))
            fields.append(content.provenanceDescription(meal))

            rows.append(fields.map(Self.escape).joined(separator: ","))
        }

        return ExportDocument(
            filename: "MealNotes-\(dates.day(generatedAt)).csv",
            format: format,
            text: rows.joined(separator: "\n")
        )
    }

    static func escape(_ field: String) -> String {
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
