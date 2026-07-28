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

    /// Set once she corrects the meal, so the screen shows the corrected version
    /// without having to go back and come in again.
    @State private var corrected: MealSnapshot?
    @State private var showingCorrection = false

    private var current: MealSnapshot { corrected ?? meal }

    private var shownRules: [GERDRule] {
        current.shownRuleIDs.compactMap { environment.rulesEngine.rule(withID: $0) }
    }

    private var confirmed: [FoodFact] {
        current.facts.filter { $0.isPresent && $0.isStrongEnoughToWarn }
    }

    private var presentCategories: Set<FoodCategory> {
        Set(current.facts.filter(\.isPresent).map(\.category))
    }

    var body: some View {
        List {
            Section {
                detailRow(
                    "When",
                    value: current.consumedAt.formatted(date: .abbreviated, time: .shortened),
                    identifier: "detail.when"
                )
                if let checkIn = current.checkIn {
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
                Section {
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
                } header: {
                    Text("Notes shown at the time")
                } footer: {
                    // Otherwise removing an ingredient and seeing its note still
                    // sitting here reads as a bug rather than as the record.
                    Text("These are what you saw at the time. Changing a meal later does not rewrite them.")
                }
            }

            if !current.corrections.isEmpty {
                Section("What you corrected") {
                    ForEach(current.corrections) { correction in
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
                if current.provenance.usedManualEntry {
                    Text("You typed this in.")
                } else {
                    if let proposed = current.provenance.proposedName {
                        Text("The app suggested “\(proposed)”.")
                    }
                    if current.provenance.repairAttempted {
                        Text("The first reading was unusable, so it was asked for again.")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(current.provenance.limitations, id: \.self) { limitation in
                    Text(limitation).font(.footnote).foregroundStyle(.secondary)
                }
                Text(current.retainedPhoto ? "A photo was kept." : "No photo was kept.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("How this was identified")
            }

        }
        .navigationTitle(current.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("meal.detail")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // In the toolbar rather than at the foot of the list: this is the
                // one thing she can *do* here, and it should not be below a
                // screenful of provenance she has to scroll past to find.
                Button("Change") { showingCorrection = true }
                    .accessibilityIdentifier("detail.correct")
                    .accessibilityHint("Corrects the name or ingredients, and what your patterns are counted from")
            }
        }
        .sheet(isPresented: $showingCorrection) {
            CorrectionView(
                initialName: current.displayName,
                initialCategories: presentCategories
            ) { name, categories in
                if let updated = environment.correctMeal(id: current.id, name: name, categories: categories) {
                    corrected = updated
                }
            }
        }
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
