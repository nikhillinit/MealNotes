import Foundation
import Testing
@testable import MealNotesCore

@Suite("Recognition decoding")
struct RecognitionDecodingTests {
    let decoder = RecognitionResponseDecoder()

    @Test("Every demo fixture except the failure case decodes")
    func demoFixturesDecode() throws {
        for fixture in RecognitionFixture.demoCases where fixture != .malformedResponse {
            let response = try decoder.decode(fixture.payload)
            #expect(!response.proposedName.isEmpty, "\(fixture.rawValue)")
            #expect(response.schemaVersion == RecognitionLimits.supportedSchemaVersion)
        }
    }

    @Test("The tea fixture proposes one question about caffeine")
    func teaFixture() throws {
        let response = try decoder.decode(RecognitionFixture.caffeinatedTea.payload)

        #expect(response.proposedName == "Black tea")
        #expect(response.clarifications.map(\.category) == [.caffeine])
        #expect(response.clarifications.first?.question == "Was the tea caffeinated?")
        #expect(response.candidateFacts.first?.isStrongEnoughToWarn == false)
    }

    @Test("Truncated JSON is rejected, not half-read")
    func malformedPayloadThrows() {
        #expect(throws: RecognitionError.self) {
            try decoder.decode(RecognitionFixture.malformedResponse.payload)
        }
    }

    @Test("An empty or missing name is rejected", arguments: [
        #"{"schemaVersion":1,"proposedName":"   "}"#,
        #"{"schemaVersion":1}"#,
        #"{"schemaVersion":1,"proposedName":42}"#
    ])
    func rejectsUnusableNames(json: String) {
        #expect(throws: RecognitionError.self) {
            try decoder.decode(Data(json.utf8))
        }
    }

    @Test("An unknown schema version is rejected")
    func rejectsUnknownSchema() {
        #expect(throws: RecognitionError.unsupportedSchemaVersion(found: 99)) {
            try decoder.decode(Data(#"{"schemaVersion":99,"proposedName":"Tea"}"#.utf8))
        }
    }

    @Test("An oversized payload is rejected before parsing")
    func rejectsOversizedPayload() {
        let huge = Data(repeating: UInt8(ascii: "{"), count: RecognitionLimits.maxPayloadBytes + 1)
        #expect(throws: RecognitionError.payloadTooLarge(bytes: huge.count)) {
            try decoder.decode(huge)
        }
    }

    @Test("More than two questions are capped at two")
    func capsClarifications() throws {
        let response = try decoder.decode(RecognitionFixture.overEagerClarifications.payload)

        #expect(response.clarifications.count == RecognitionLimits.maxClarificationQuestions)
        #expect(response.clarifications.count == 2)
        #expect(response.decodingNotes.contains { $0.contains("clarification") })
    }

    @Test("Unknown values are dropped rather than guessed at")
    func dropsUnknownEntries() throws {
        let response = try decoder.decode(RecognitionFixture.unknownCategories.payload)

        // "gluten" and "witchcraft" are not categories this app reasons about.
        #expect(response.ingredientCandidates.map(\.category) == [.tomato])
        // A component with no name is unusable.
        #expect(response.components.map(\.name) == ["Broth"])
        // The user cannot answer a question about the clock.
        #expect(response.clarifications.isEmpty)
        #expect(!response.decodingNotes.isEmpty)
    }

    @Test("Oversized and out-of-range values are bounded")
    func boundsHostileValues() throws {
        let response = try decoder.decode(RecognitionFixture.hostileStrings.payload)

        #expect(response.proposedName.count == RecognitionLimits.maxStringLength)
        #expect(response.proposedNameConfidence == 1.0)
        #expect(response.overallConfidence == 0.0)
        #expect(response.components.first?.confidence == 1.0)
        #expect(response.components.first?.name == "spaced out")
        // An unrecognised source falls back to the least trusted option.
        #expect(response.components.first?.source == .visualInference)
        #expect(response.ingredientCandidates.first?.label.count == RecognitionLimits.maxStringLength)
        #expect(response.limitations == ["A real limitation."])
    }

    @Test("A decoded response never exceeds its own limits")
    func respectsAllLimits() throws {
        for fixture in RecognitionFixture.allCases where fixture != .malformedResponse {
            let response = try decoder.decode(fixture.payload)
            #expect(response.clarifications.count <= RecognitionLimits.maxClarificationQuestions)
            #expect(response.components.count <= RecognitionLimits.maxComponents)
            #expect(response.ingredientCandidates.count <= RecognitionLimits.maxIngredientCandidates)
            #expect(response.limitations.count <= RecognitionLimits.maxLimitations)
            #expect(response.proposedName.count <= RecognitionLimits.maxStringLength)
        }
    }
}

@Suite("Recognition coordination and failure handling")
struct RecognitionCoordinatorTests {
    @Test("A good payload is identified with no repair")
    func happyPath() async throws {
        let client = MockRecognitionClient()
        let outcome = await RecognitionCoordinator(client: client)
            .identify(RecognitionRequest(imageIdentifier: RecognitionFixture.salmonWithCouscous.rawValue))

        #expect(outcome.response?.proposedName == "Salmon with couscous")
        #expect(outcome.repairAttempted == false)
        #expect(await client.repairCallCount == 0)
    }

    @Test("A malformed payload is retried exactly once, then falls back to typing")
    func repairsOnceThenFallsBack() async throws {
        let client = MockRecognitionClient()
        let outcome = await RecognitionCoordinator(client: client)
            .identify(RecognitionRequest(imageIdentifier: RecognitionFixture.malformedResponse.rawValue))

        #expect(await client.recognizeCallCount == 1)
        #expect(await client.repairCallCount == 1, "exactly one repair attempt")
        #expect(outcome.repairAttempted)
        #expect(outcome.response == nil)

        guard case .malformedResponse = try #require(outcome.manualEntryReason) else {
            Issue.record("expected a malformed-response fallback")
            return
        }
    }

    @Test("A successful repair is used")
    func repairCanSucceed() async throws {
        let client = MockRecognitionClient(repairSucceedsWith: .caffeinatedTea)
        let outcome = await RecognitionCoordinator(client: client)
            .identify(RecognitionRequest(imageIdentifier: RecognitionFixture.malformedResponse.rawValue))

        #expect(outcome.response?.proposedName == "Black tea")
        #expect(outcome.repairAttempted)
        #expect(await client.repairCallCount == 1)
    }

    @Test("Offline falls back to typing without attempting a repair")
    func offlineFallsBack() async throws {
        let client = MockRecognitionClient(offline: true)
        let outcome = await RecognitionCoordinator(client: client)
            .identify(RecognitionRequest(imageIdentifier: RecognitionFixture.caffeinatedTea.rawValue))

        #expect(outcome.manualEntryReason == .serviceUnavailable)
        #expect(outcome.repairAttempted == false)
        #expect(await client.repairCallCount == 0)
    }

    @Test("When recognition fails, no note is shown at all")
    func failureProducesNoWarning() async throws {
        let client = MockRecognitionClient()
        let outcome = await RecognitionCoordinator(client: client)
            .identify(RecognitionRequest(imageIdentifier: RecognitionFixture.malformedResponse.rawValue))

        // There are no facts to reason about, so the engine has nothing to say.
        let facts = outcome.response?.candidateFacts ?? []
        #expect(facts.isEmpty)

        let evaluation = GERDRulesEngine().evaluate(facts: facts)
        #expect(evaluation.hasWarning == false)
        #expect(evaluation.warnings.isEmpty)
        #expect(evaluation.unconfirmedMaterialFacts.isEmpty)
    }

    @Test("A low-confidence identification is still offered, not discarded")
    func lowConfidenceStillIdentifies() async throws {
        let outcome = await RecognitionCoordinator(client: MockRecognitionClient())
            .identify(RecognitionRequest(imageIdentifier: RecognitionFixture.unknownItem.rawValue))

        let response = try #require(outcome.response)
        #expect(response.proposedName == "Mixed dish")
        #expect(response.proposedNameConfidence < 0.5)
        #expect(GERDRulesEngine().evaluate(facts: response.candidateFacts).hasWarning == false)
    }
}

@Suite("Recognition privacy")
struct RecognitionPrivacyTests {
    /// The only things that may be sent for one capture.
    static let allowedFields: Set<String> = [
        "imageIdentifier", "imageData", "detectedBarcode", "detectedLabelText", "instructions"
    ]

    @Test("A recognition request carries nothing but the current capture")
    func requestCarriesOnlyTheCapture() {
        let request = RecognitionRequest(imageIdentifier: "fixture", detectedBarcode: "123")
        let fields = Set(Mirror(reflecting: request).children.compactMap(\.label))

        #expect(fields == Self.allowedFields, "unexpected fields: \(fields.subtracting(Self.allowedFields))")
    }

    @Test("The default instructions ask for identification, not advice")
    func instructionsDoNotAskForAdvice() {
        let instructions = RecognitionRequest.defaultInstructions.lowercased()
        #expect(instructions.contains("do not give health"))
        #expect(instructions.contains("medical advice"))
        #expect(instructions.contains("identify"))
    }
}
