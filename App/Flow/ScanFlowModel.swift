import Foundation
import MealNotesCore
import Observation

/// Drives one capture from picking an image through to a logged meal.
///
/// The model owns the sequence; it never decides what a warning says. It asks
/// ``GERDRulesEngine`` after every change to the facts and shows whatever comes
/// back, including nothing.
@MainActor
@Observable
final class ScanFlowModel {
    enum Stage: Equatable {
        case choosing
        case identifying
        case asking
        case result
        case manualEntry
        case logged
    }

    private let environment: AppEnvironment

    private(set) var stage: Stage = .choosing
    private(set) var consumedAt: Date = .distantPast
    private(set) var itemName: String = ""
    private(set) var facts: [FoodFact] = []
    private(set) var evaluation: GERDEvaluation = .none
    private(set) var questions: [ClarificationQuestion] = []
    private(set) var questionIndex: Int = 0
    private(set) var limitations: [String] = []
    private(set) var personalNote: String?
    private(set) var corrections: [MealCorrection] = []
    private(set) var provenance: RecognitionProvenance = .manualEntry
    private(set) var manualEntryReason: ManualEntryReason?
    private(set) var identificationIsUncertain = false
    private(set) var loggedMeal: LoggedMeal?

    /// Bound to the text field on the manual-entry and no-photo screens.
    var typedName: String = ""

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var currentQuestion: ClarificationQuestion? {
        questions.indices.contains(questionIndex) ? questions[questionIndex] : nil
    }

    var questionProgress: String {
        "Question \(questionIndex + 1) of \(questions.count)"
    }

    /// Categories currently believed to be present, for the correction screen.
    var presentCategories: Set<FoodCategory> {
        Set(evaluation.resolvedFacts.filter(\.isPresent).map(\.category))
    }

    // MARK: - Capture

    func begin(fixture: RecognitionFixture) async {
        stage = .identifying
        consumedAt = environment.dates.now()

        do {
            let image = try await environment.captureService.capture(identifier: fixture.rawValue)
            let findings = await environment.scanner.scan(image)
            let productFacts = await lookUpProduct(barcode: findings.barcode)

            // Only the current image and the minimum needed to read it.
            let request = RecognitionRequest(
                imageIdentifier: image.identifier,
                imageData: image.data,
                detectedBarcode: findings.barcode,
                detectedLabelText: findings.labelText
            )
            let outcome = await environment.recognition.identify(request)

            switch outcome.resolution {
            case .identified(let response):
                accept(response, fixture: fixture, outcome: outcome, productFacts: productFacts)
            case .manualEntryRequired(let reason):
                fallBackToTyping(reason: reason, fixture: fixture, outcome: outcome)
            }
        } catch {
            AppLog.flow.error("Capture failed: \(error, privacy: .public)")
            fallBackToTyping(reason: .serviceUnavailable, fixture: fixture, outcome: nil)
        }
    }

    /// Starts a log with no photo at all — used when offline, or when a photo is
    /// not wanted. No note is shown, because nothing has been established.
    func beginManualEntry() {
        consumedAt = environment.dates.now()
        provenance = .manualEntry
        manualEntryReason = nil
        stage = .manualEntry
    }

    private func lookUpProduct(barcode: String?) async -> [FoodFact] {
        guard let barcode else { return [] }
        do {
            guard let product = try await environment.productLookup.product(barcode: barcode) else { return [] }
            return product.categories.map {
                FoodFact(category: $0, source: .barcodeDatabase, confidence: 0.9, detail: product.name)
            }
        } catch {
            // A lookup that fails is not a failure of the capture: carry on with
            // label text and visual recognition.
            AppLog.flow.info("Product lookup unavailable: \(error, privacy: .public)")
            return []
        }
    }

    private func accept(
        _ response: RecognitionResponse,
        fixture: RecognitionFixture,
        outcome: RecognitionOutcome,
        productFacts: [FoodFact]
    ) {
        itemName = response.proposedName
        typedName = response.proposedName
        facts = productFacts + response.candidateFacts
        limitations = response.limitations
        identificationIsUncertain = response.proposedNameConfidence < 0.5
        provenance = RecognitionProvenance(
            fixtureID: fixture.rawValue,
            proposedName: response.proposedName,
            overallConfidence: response.overallConfidence,
            repairAttempted: outcome.repairAttempted,
            usedManualEntry: false,
            limitations: response.limitations
        )

        reevaluate()
        questions = ClarificationPlanner.questions(response: response, evaluation: evaluation)
        questionIndex = 0
        stage = questions.isEmpty ? .result : .asking
    }

    private func fallBackToTyping(
        reason: ManualEntryReason,
        fixture: RecognitionFixture,
        outcome: RecognitionOutcome?
    ) {
        manualEntryReason = reason
        provenance = RecognitionProvenance(
            fixtureID: fixture.rawValue,
            repairAttempted: outcome?.repairAttempted ?? false,
            usedManualEntry: true
        )
        facts = []
        evaluation = .none
        typedName = ""
        stage = .manualEntry
    }

    // MARK: - Questions

    func answerCurrentQuestion(_ isPresent: Bool) {
        guard let question = currentQuestion else { return }
        facts.append(question.answer(isPresent))
        questionIndex += 1

        if currentQuestion == nil {
            reevaluate()
            stage = .result
        }
    }

    /// "I'm not sure" — moves on without asserting anything either way, so the
    /// guess stays a guess and no note is produced from it.
    func skipCurrentQuestion() {
        guard currentQuestion != nil else { return }
        questionIndex += 1

        if currentQuestion == nil {
            reevaluate()
            stage = .result
        }
    }

    func skipAllQuestions() {
        questionIndex = questions.count
        reevaluate()
        stage = .result
    }

    // MARK: - Corrections

    func applyCorrection(name: String, categories: Set<FoodCategory>) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = environment.dates.now()

        if !trimmed.isEmpty, trimmed != itemName {
            corrections.append(
                MealCorrection(createdAt: now, field: .name, previousValue: itemName, newValue: trimmed)
            )
            itemName = trimmed
        }

        let before = presentCategories
        let added = categories.subtracting(before)
        let removed = before.subtracting(categories)

        if !added.isEmpty || !removed.isEmpty {
            corrections.append(
                MealCorrection(
                    createdAt: now,
                    field: .ingredients,
                    previousValue: Self.describe(before),
                    newValue: Self.describe(categories)
                )
            )
            facts.append(contentsOf: added.map { FoodFact.confirmed($0, isPresent: true) })
            facts.append(contentsOf: removed.map { FoodFact.confirmed($0, isPresent: false) })
        }

        reevaluate()
    }

    private static func describe(_ categories: Set<FoodCategory>) -> String {
        categories.isEmpty ? "none" : categories.map(\.displayName).sorted().joined(separator: ", ")
    }

    // MARK: - Logging

    func confirmConsumption() async {
        let draft = MealDraft(
            consumedAt: consumedAt,
            displayName: itemName,
            facts: FactResolver.resolve(facts),
            // What was actually on screen, so the record can be reproduced.
            shownRuleIDs: evaluation.displayWarnings.map(\.ruleID),
            corrections: corrections,
            provenance: provenance,
            // Milestone 1 never retains a photo.
            retainedPhotoData: nil
        )
        await log(draft)
    }

    func logTypedEntry() async {
        let trimmed = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        itemName = trimmed
        facts = []
        // Recognition did not establish anything, so nothing is claimed about it.
        evaluation = .none

        await log(
            MealDraft(
                consumedAt: consumedAt,
                displayName: trimmed,
                facts: [],
                shownRuleIDs: [],
                corrections: corrections,
                provenance: provenance
            )
        )
    }

    private func log(_ draft: MealDraft) async {
        do {
            loggedMeal = try await environment.mealLogger.log(draft)
            stage = .logged
            environment.refresh()
            await environment.requestNotificationPermissionIfNeeded()
        } catch {
            AppLog.store.error("Could not log the meal: \(error, privacy: .public)")
        }
    }

    private func reevaluate() {
        evaluation = environment.rulesEngine.evaluate(
            facts: facts,
            context: MealContext(consumedAt: consumedAt)
        )
        let confirmed = Set(
            evaluation.resolvedFacts.filter { $0.isPresent && $0.isStrongEnoughToWarn }.map(\.category)
        )
        personalNote = confirmed.isEmpty ? nil : environment.personalNote(for: confirmed)
    }
}
