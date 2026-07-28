import Foundation

/// Everything sent to a recognition provider for one capture.
///
/// This type is deliberately narrow. It carries the current image and the
/// minimum needed to interpret it — and structurally cannot carry meal history,
/// symptom history, or anything else about the user. `RecognitionPrivacyTests`
/// asserts that this stays true.
public struct RecognitionRequest: Sendable, Hashable {
    /// Opaque handle for the capture. In Milestone 1 this is a fixture name.
    public let imageIdentifier: String
    public let imageData: Data?
    /// Barcode read on-device, if one was visible.
    public let detectedBarcode: String?
    /// Label text read on-device, if any was legible.
    public let detectedLabelText: [String]
    /// The only instruction text sent alongside the image.
    public let instructions: String

    public init(
        imageIdentifier: String,
        imageData: Data? = nil,
        detectedBarcode: String? = nil,
        detectedLabelText: [String] = [],
        instructions: String = RecognitionRequest.defaultInstructions
    ) {
        self.imageIdentifier = imageIdentifier
        self.imageData = imageData
        self.detectedBarcode = detectedBarcode
        self.detectedLabelText = detectedLabelText
        self.instructions = instructions
    }

    /// Identification only. The provider is explicitly not asked for advice —
    /// warnings come from ``GERDRulesEngine`` and nowhere else.
    public static let defaultInstructions = """
        Identify the food or drink in this image. Return only the JSON described \
        by the schema: a proposed name, visible components, candidate ingredient \
        categories with confidence and source, at most two clarification \
        questions, and any limitations. Do not give health, dietary or medical \
        advice. Do not infer anything about the person.
        """
}

/// Raw bytes back from a provider, plus which provider produced them.
public struct RecognitionEnvelope: Sendable, Hashable {
    public let payload: Data
    public let providerID: String

    public init(payload: Data, providerID: String) {
        self.payload = payload
        self.providerID = providerID
    }
}

/// A source of visual identification.
///
/// Implementations return *bytes*, not decoded models, so that validation always
/// happens in one place and provider output is never trusted implicitly.
public protocol RecognitionClient: Sendable {
    func recognize(_ request: RecognitionRequest) async throws -> RecognitionEnvelope

    /// One retry with a repair instruction after a payload failed to decode.
    func repair(
        _ request: RecognitionRequest,
        previousPayload: Data,
        failure: RecognitionError
    ) async throws -> RecognitionEnvelope
}

public enum ManualEntryReason: Sendable, Hashable {
    case malformedResponse(String)
    case serviceUnavailable

    /// Calm, non-technical copy for the user.
    public var userMessage: String {
        switch self {
        case .malformedResponse:
            "The photo could not be read this time. You can type the name instead."
        case .serviceUnavailable:
            "Identifying photos is not available right now. You can type the name instead."
        }
    }
}

public struct RecognitionOutcome: Sendable, Hashable {
    public enum Resolution: Sendable, Hashable {
        case identified(RecognitionResponse)
        case manualEntryRequired(ManualEntryReason)
    }

    public let resolution: Resolution
    public let repairAttempted: Bool
    public let providerID: String?

    public init(resolution: Resolution, repairAttempted: Bool, providerID: String?) {
        self.resolution = resolution
        self.repairAttempted = repairAttempted
        self.providerID = providerID
    }

    public var response: RecognitionResponse? {
        if case .identified(let response) = resolution { return response }
        return nil
    }

    public var manualEntryReason: ManualEntryReason? {
        if case .manualEntryRequired(let reason) = resolution { return reason }
        return nil
    }
}

/// Runs a recognition request through decode → single repair → manual fallback.
///
/// The app never sees an undecoded payload, and a provider can never push the
/// user into a dead end: the worst case is typing a name.
public struct RecognitionCoordinator: Sendable {
    private let client: any RecognitionClient
    private let decoder: RecognitionResponseDecoder

    public init(client: any RecognitionClient, decoder: RecognitionResponseDecoder = RecognitionResponseDecoder()) {
        self.client = client
        self.decoder = decoder
    }

    public func identify(_ request: RecognitionRequest) async -> RecognitionOutcome {
        let envelope: RecognitionEnvelope
        do {
            envelope = try await client.recognize(request)
        } catch {
            return RecognitionOutcome(
                resolution: .manualEntryRequired(.serviceUnavailable),
                repairAttempted: false,
                providerID: nil
            )
        }

        do {
            let response = try decoder.decode(envelope.payload)
            return RecognitionOutcome(
                resolution: .identified(response),
                repairAttempted: false,
                providerID: envelope.providerID
            )
        } catch let firstFailure {
            let failure = (firstFailure as? RecognitionError) ?? .malformed("unreadable payload")
            return await repairOnce(request, previousPayload: envelope.payload, failure: failure)
        }
    }

    private func repairOnce(
        _ request: RecognitionRequest,
        previousPayload: Data,
        failure: RecognitionError
    ) async -> RecognitionOutcome {
        do {
            let repaired = try await client.repair(request, previousPayload: previousPayload, failure: failure)
            let response = try decoder.decode(repaired.payload)
            return RecognitionOutcome(
                resolution: .identified(response),
                repairAttempted: true,
                providerID: repaired.providerID
            )
        } catch {
            let reason = (error as? RecognitionError) ?? failure
            if case .serviceUnavailable = reason {
                return RecognitionOutcome(
                    resolution: .manualEntryRequired(.serviceUnavailable),
                    repairAttempted: true,
                    providerID: nil
                )
            }
            return RecognitionOutcome(
                resolution: .manualEntryRequired(.malformedResponse(reason.shortReason)),
                repairAttempted: true,
                providerID: nil
            )
        }
    }
}
