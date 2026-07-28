import MealNotesCore
import SwiftUI

/// The later "how did that go?" question.
///
/// Severity is one tap. Everything after it is optional, so the fastest possible
/// answer — "Fine" — is two taps including Save.
struct CheckInView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let window: CheckInWindowSnapshot

    @State private var severity: CheckInSeverity?
    @State private var symptoms: Set<SymptomTag> = []
    @State private var urgentSymptoms: Set<UrgentSymptom> = []
    @State private var isSaving = false

    private var meals: [MealSnapshot] {
        environment.meals(withIDs: window.mealIDs)
    }

    var body: some View {
        NavigationStack {
            List {
                if !meals.isEmpty {
                    Section("After") {
                        ForEach(meals) { meal in
                            HStack {
                                Text(meal.displayName)
                                Spacer()
                                Text(meal.consumedAt.formatted(date: .omitted, time: .shortened))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(minHeight: Layout.minimumTouchTarget)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                Section("How are you feeling after your meal?") {
                    ForEach(CheckInSeverity.allCases) { option in
                        SelectableRow(
                            title: option.displayName,
                            systemImage: option.symbolName,
                            isSelected: severity == option,
                            identifier: "checkin.severity.\(option.rawValue)"
                        ) {
                            severity = option
                            if option == .fine {
                                symptoms.removeAll()
                                urgentSymptoms.removeAll()
                            }
                        }
                    }
                }

                if severity?.indicatesSymptoms == true {
                    Section {
                        ForEach(SymptomTag.allCases) { tag in
                            SelectableRow(
                                title: tag.displayName,
                                isSelected: symptoms.contains(tag),
                                identifier: "checkin.symptom.\(tag.rawValue)"
                            ) {
                                toggle(tag)
                            }
                        }
                    } header: {
                        Text("Anything you noticed?")
                    } footer: {
                        Text("Optional — skip this if you would rather.")
                    }

                    Section {
                        ForEach(UrgentSymptom.allCases) { symptom in
                            SelectableRow(
                                title: symptom.displayName,
                                isSelected: urgentSymptoms.contains(symptom),
                                identifier: "checkin.urgent.\(symptom.rawValue)"
                            ) {
                                toggle(symptom)
                            }
                        }
                    } header: {
                        // The list that matters most had the vaguest label. Heading,
                        // icon and words together, never colour alone.
                        Label("Worth mentioning to a doctor", systemImage: "stethoscope")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .accessibilityAddTraits(.isHeader)
                    } footer: {
                        Text("Recording one of these here is not the same as getting it looked at.")
                    }
                }
            }
            .navigationTitle("Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                        .accessibilityIdentifier("checkin.dismiss")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(severity == nil || isSaving)
                        .accessibilityIdentifier("checkin.save")
                }
            }
        }
    }

    private func save() {
        guard let severity else { return }
        isSaving = true
        Task {
            await environment.recordCheckIn(
                windowID: window.id,
                severity: severity,
                symptoms: SymptomTag.allCases.filter(symptoms.contains),
                urgentSymptoms: UrgentSymptom.allCases.filter(urgentSymptoms.contains)
            )
            dismiss()
        }
    }

    private func toggle(_ tag: SymptomTag) {
        if symptoms.contains(tag) { symptoms.remove(tag) } else { symptoms.insert(tag) }
    }

    private func toggle(_ symptom: UrgentSymptom) {
        if urgentSymptoms.contains(symptom) { urgentSymptoms.remove(symptom) } else { urgentSymptoms.insert(symptom) }
    }
}
