import MealNotesCore
import SwiftUI

/// The capture-to-logged journey, in one screen that changes what it shows.
struct ScanFlowView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let startByTyping: Bool

    @State private var model: ScanFlowModel?
    @State private var showingCorrection = false

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("scan.close")
                }
            }
        }
        .task {
            guard model == nil else { return }
            let created = ScanFlowModel(environment: environment)
            if startByTyping { created.beginManualEntry() }
            model = created
        }
    }

    @ViewBuilder
    private func content(_ model: ScanFlowModel) -> some View {
        switch model.stage {
        case .choosing: CapturePickerView(model: model)
        case .identifying: identifying
        case .asking: ClarificationView(model: model)
        case .result: ResultView(model: model, showingCorrection: $showingCorrection)
        case .manualEntry: TypeItInView(model: model)
        case .logged: LoggedView(model: model) { dismiss() }
        }
    }

    private var identifying: some View {
        VStack(spacing: 20) {
            ProgressView().controlSize(.large)
            Text("Looking at your photo…")
                .font(.title3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("One moment")
        .accessibilityIdentifier("scan.identifying")
    }
}

// MARK: - Capture

struct CapturePickerView: View {
    @Bindable var model: ScanFlowModel

    var body: some View {
        List {
            Section {
                ForEach(RecognitionFixture.demoCases) { fixture in
                    Button {
                        Task { await model.begin(fixture: fixture) }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fixture.title).font(.body.weight(.medium))
                                Text(fixture.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: fixture.symbolName).imageScale(.large)
                        }
                        .frame(minHeight: Layout.minimumTouchTarget)
                    }
                    .accessibilityIdentifier("capture.fixture.\(fixture.rawValue)")
                }
            } header: {
                Text("Choose an example photo")
            } footer: {
                Text("""
                    This early version uses saved example photos so the whole \
                    flow can be tried without a camera. The camera and your photo \
                    library come next.
                    """)
            }
        }
        .navigationTitle("Scan")
    }
}

// MARK: - Questions

struct ClarificationView: View {
    @Bindable var model: ScanFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let question = model.currentQuestion {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.questionProgress)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(question.question)
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                }

                VStack(spacing: 12) {
                    PrimaryButton(title: "Yes") { model.answerCurrentQuestion(true) }
                        .accessibilityIdentifier("clarify.yes")
                    PrimaryButton(title: "No") { model.answerCurrentQuestion(false) }
                        .accessibilityIdentifier("clarify.no")
                    SecondaryButton(title: "I'm not sure") { model.skipCurrentQuestion() }
                        .accessibilityIdentifier("clarify.unsure")
                }

                QuietNote(text: "This helps the app avoid guessing. It is never required.")
            }

            Spacer()
        }
        .padding()
        .navigationTitle(model.itemName.isEmpty ? "One question" : model.itemName)
    }
}

// MARK: - Result

struct ResultView: View {
    @Environment(AppEnvironment.self) private var environment
    @Bindable var model: ScanFlowModel
    @Binding var showingCorrection: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Looks like")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(model.itemName)
                        .font(.largeTitle.weight(.semibold))
                        .accessibilityIdentifier("result.itemName")
                        .accessibilityAddTraits(.isHeader)
                }

                if model.identificationIsUncertain {
                    QuietNote(
                        text: "The photo was not clear, so this is a rough guess. Please check the name.",
                        systemImage: "questionmark.circle"
                    )
                }

                ForEach(Array(model.evaluation.displayWarnings.enumerated()), id: \.element.id) { index, warning in
                    WarningCard(warning: warning, showHeading: index == 0)
                }

                if let note = model.personalNote {
                    QuietNote(text: note, systemImage: "clock.arrow.circlepath")
                        .accessibilityIdentifier("result.personalNote")
                }

                if let limitation = model.limitations.first {
                    QuietNote(text: limitation)
                }

                VStack(spacing: 12) {
                    PrimaryButton(title: "I'm having this", systemImage: "checkmark") {
                        Task { await model.confirmConsumption() }
                    }
                    .accessibilityIdentifier("result.confirm")

                    SecondaryButton(title: "Change name or ingredients", systemImage: "pencil") {
                        showingCorrection = true
                    }
                    .accessibilityIdentifier("result.correct")
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .navigationTitle("What we found")
        .sheet(isPresented: $showingCorrection) {
            CorrectionView(
                initialName: model.itemName,
                initialCategories: model.presentCategories
            ) { name, categories in
                model.applyCorrection(name: name, categories: categories)
            }
        }
    }
}

struct CorrectionView: View {
    @Environment(\.dismiss) private var dismiss

    let initialName: String
    let initialCategories: Set<FoodCategory>
    let onSave: (String, Set<FoodCategory>) -> Void

    @State private var name: String = ""
    @State private var categories: Set<FoodCategory> = []

    private var editable: [FoodCategory] {
        FoodCategory.allCases.filter(\.isUserAnswerable)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("What was it?", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("correct.name")
                }

                Section {
                    ForEach(editable, id: \.self) { category in
                        Toggle(category.displayName, isOn: binding(for: category))
                            .frame(minHeight: Layout.minimumTouchTarget)
                    }
                } header: {
                    Text("What was in it")
                } footer: {
                    Text("Anything you confirm here is used instead of what the photo suggested.")
                }
            }
            .navigationTitle("Correct this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, categories)
                        dismiss()
                    }
                    .accessibilityIdentifier("correct.save")
                }
            }
        }
        .onAppear {
            name = initialName
            categories = initialCategories
        }
    }

    private func binding(for category: FoodCategory) -> Binding<Bool> {
        Binding(
            get: { categories.contains(category) },
            set: { isOn in
                if isOn { categories.insert(category) } else { categories.remove(category) }
            }
        )
    }
}

// MARK: - Typing it in

struct TypeItInView: View {
    @Bindable var model: ScanFlowModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let reason = model.manualEntryReason {
                QuietNote(text: reason.userMessage, systemImage: "exclamationmark.circle")
                    .accessibilityIdentifier("manual.reason")
            }

            TextField("What did you have?", text: $model.typedName)
                .font(.title3)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.sentences)
                .focused($focused)
                .accessibilityIdentifier("manual.name")

            PrimaryButton(
                title: "I'm having this",
                systemImage: "checkmark",
                isEnabled: !model.typedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                Task { await model.logTypedEntry() }
            }
            .accessibilityIdentifier("manual.confirm")

            QuietNote(text: "No note is shown for a meal the app could not identify.")

            Spacer()
        }
        .padding()
        .navigationTitle("Type it in")
        .onAppear { focused = true }
    }
}

// MARK: - Done

struct LoggedView: View {
    @Bindable var model: ScanFlowModel
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .accessibilityHidden(true)

            Text("Saved")
                .font(.largeTitle.weight(.semibold))
                .accessibilityIdentifier("logged.confirmation")

            if let logged = model.loggedMeal {
                Text("We'll ask how you're feeling at \(logged.checkInDueAt.formatted(date: .omitted, time: .shortened)).")
                    .font(.title3)
                    .multilineTextAlignment(.center)

                if logged.joinedExistingWindow {
                    QuietNote(text: "Added to your last meal, so there is still just one check-in.")
                }
            }

            PrimaryButton(title: "Done", action: onDone)
                .accessibilityIdentifier("logged.done")
                .padding(.top)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("")
    }
}
