import MealNotesCore
import SwiftUI

struct HistoryView: View {
    @Environment(AppEnvironment.self) private var environment

    private var groups: [(day: String, meals: [MealSnapshot])] {
        let meals = environment.allMeals()
        var order: [String] = []
        var byDay: [String: [MealSnapshot]] = [:]

        for meal in meals {
            let day = meal.consumedAt.formatted(date: .complete, time: .omitted)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(meal)
        }
        return order.map { (day: $0, meals: byDay[$0] ?? []) }
    }

    var body: some View {
        List {
            if groups.isEmpty {
                ContentUnavailableView(
                    "Nothing recorded yet",
                    systemImage: "fork.knife",
                    description: Text("Meals you log will appear here.")
                )
            }

            ForEach(groups, id: \.day) { group in
                Section(group.day) {
                    ForEach(group.meals) { meal in
                        NavigationLink { MealDetailView(meal: meal) } label: { MealRow(meal: meal) }
                    }
                }
            }
        }
        .navigationTitle("All meals")
        .accessibilityIdentifier("history.list")
        .toolbar { ExportMenu() }
    }
}

struct MealDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    let meal: MealSnapshot

    private var shownRules: [GERDRule] {
        meal.shownRuleIDs.compactMap { environment.rulesEngine.rule(withID: $0) }
    }

    private var confirmed: [FoodFact] {
        meal.facts.filter { $0.isPresent && $0.isStrongEnoughToWarn }
    }

    var body: some View {
        List {
            Section {
                detailRow(
                    "When",
                    value: meal.consumedAt.formatted(date: .abbreviated, time: .shortened),
                    identifier: "detail.when"
                )
                if let checkIn = meal.checkIn {
                    detailRow("How you felt", value: checkIn.severity.displayName, identifier: "detail.severity")
                    if !checkIn.symptoms.isEmpty {
                        detailRow(
                            "Noticed",
                            value: checkIn.symptoms.map(\.displayName).joined(separator: ", "),
                            identifier: "detail.symptoms"
                        )
                    }
                    if !checkIn.urgentSymptoms.isEmpty {
                        detailRow(
                            "Also recorded",
                            value: checkIn.urgentSymptoms.map(\.displayName).joined(separator: ", "),
                            identifier: "detail.urgentSymptoms"
                        )
                    }
                } else {
                    Text("No check-in answer yet").foregroundStyle(.secondary)
                }
            } header: {
                Text(meal.displayName).font(.title3.weight(.semibold))
            }

            if !confirmed.isEmpty {
                Section("What was in it") {
                    ForEach(confirmed) { fact in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fact.category.displayName)
                            Text(fact.source.displayName)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if !shownRules.isEmpty {
                Section("Notes shown at the time") {
                    ForEach(shownRules) { rule in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(rule.title).font(.body.weight(.medium))
                            Text(rule.explanation).font(.footnote)
                            Text(rule.suggestion).font(.footnote).foregroundStyle(.secondary)
                            ForEach(rule.sources, id: \.url) { source in
                                Link(source.title, destination: source.url).font(.caption)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if !meal.corrections.isEmpty {
                Section("What you corrected") {
                    ForEach(meal.corrections) { correction in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(correction.field.displayName).font(.footnote.weight(.medium))
                            Text("\(correction.previousValue) → \(correction.newValue)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Section {
                if meal.provenance.usedManualEntry {
                    Text("You typed this in.")
                } else {
                    if let proposed = meal.provenance.proposedName {
                        Text("The app suggested “\(proposed)”.")
                    }
                    if meal.provenance.repairAttempted {
                        Text("The first reading was unusable, so it was asked for again.")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(meal.provenance.limitations, id: \.self) { limitation in
                    Text(limitation).font(.footnote).foregroundStyle(.secondary)
                }
                Text(meal.retainedPhoto ? "A photo was kept." : "No photo was kept.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("How this was identified")
            }
        }
        .navigationTitle(meal.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("meal.detail")
    }

    /// Read as one phrase by VoiceOver rather than as two disconnected fragments.
    private func detailRow(_ title: String, value: String, identifier: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
