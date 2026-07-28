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
                        Text("Anything else?")
                    } footer: {
                        Text("These are worth mentioning to a doctor rather than only noting here.")
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

/// A full-width tappable row with a checkmark.
///
/// Used instead of a `Toggle` throughout the check-in: the whole row is the
/// target rather than a small switch at the edge, which matters a great deal for
/// anyone with less steady hands.
struct SelectableRow: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
                Spacer(minLength: 12)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Layout.minimumTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
