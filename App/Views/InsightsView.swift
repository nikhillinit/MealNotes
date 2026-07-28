import MealNotesCore
import SwiftUI

struct InsightsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        List {
            ForEach(environment.insights) { insight in
                if insight.isActionable {
                    NavigationLink {
                        InsightMealsView(insight: insight)
                    } label: {
                        InsightRow(insight: insight)
                    }
                    .accessibilityIdentifier("insight.\(insight.id)")
                } else {
                    InsightRow(insight: insight)
                        .accessibilityIdentifier("insight.\(insight.id)")
                }
            }

            Section {
                Text("""
                    These are counts of what you recorded, nothing more. They \
                    cannot tell you why something happened, and they are not a \
                    diagnosis.
                    """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Patterns")
        .accessibilityIdentifier("insights.list")
        .onAppear { environment.refresh() }
    }
}

struct InsightRow: View {
    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(insight.headline)
                .font(.body.weight(.medium))
            Text(insight.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("^[\(insight.observationCount) observation](inflect: true)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct InsightMealsView: View {
    @Environment(AppEnvironment.self) private var environment
    let insight: Insight

    private var meals: [MealSnapshot] {
        environment.meals(withIDs: insight.mealIDs)
    }

    var body: some View {
        List {
            Section {
                Text(insight.headline).font(.body.weight(.medium))
                Text(insight.detail).font(.footnote).foregroundStyle(.secondary)
            }

            Section("The meals behind this") {
                ForEach(meals) { meal in
                    NavigationLink { MealDetailView(meal: meal) } label: { MealRow(meal: meal) }
                }
            }
        }
        .navigationTitle("Behind this")
        .navigationBarTitleDisplayMode(.inline)
    }
}
