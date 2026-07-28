import Foundation

/// Fixture-backed ``RecognitionClient``.
///
/// The fixture is chosen by `RecognitionRequest.imageIdentifier`, so the capture
/// picker selects behaviour simply by naming a fixture — the client itself holds
/// no per-capture state.
public actor MockRecognitionClient: RecognitionClient {
    public static let providerID = "mock.fixtures"

    private let offline: Bool
    private let repairSucceedsWith: RecognitionFixture?
    private let payloadOverride: Data?
    private let artificialDelay: Duration

    private(set) public var recognizeCallCount = 0
    private(set) public var repairCallCount = 0

    /// - Parameters:
    ///   - offline: Simulates having no connection at all.
    ///   - repairSucceedsWith: Fixture returned by the single repair attempt.
    ///     When `nil`, the repair also returns something undecodable.
    ///   - payloadOverride: Returned instead of any fixture. For tests.
    ///   - artificialDelay: Small delay so the app's loading state is visible.
    public init(
        offline: Bool = false,
        repairSucceedsWith: RecognitionFixture? = nil,
        payloadOverride: Data? = nil,
        artificialDelay: Duration = .zero
    ) {
        self.offline = offline
        self.repairSucceedsWith = repairSucceedsWith
        self.payloadOverride = payloadOverride
        self.artificialDelay = artificialDelay
    }

    public func recognize(_ request: RecognitionRequest) async throws -> RecognitionEnvelope {
        recognizeCallCount += 1
        if offline { throw RecognitionError.serviceUnavailable }
        await pause()

        if let payloadOverride {
            return RecognitionEnvelope(payload: payloadOverride, providerID: Self.providerID)
        }
        guard let fixture = RecognitionFixture(rawValue: request.imageIdentifier) else {
            throw RecognitionError.serviceUnavailable
        }
        return RecognitionEnvelope(payload: fixture.payload, providerID: Self.providerID)
    }

    public func repair(
        _ request: RecognitionRequest,
        previousPayload: Data,
        failure: RecognitionError
    ) async throws -> RecognitionEnvelope {
        repairCallCount += 1
        if offline { throw RecognitionError.serviceUnavailable }
        await pause()

        if let repairSucceedsWith {
            return RecognitionEnvelope(payload: repairSucceedsWith.payload, providerID: Self.providerID)
        }
        // A provider that "repairs" into something still undecodable is the
        // realistic bad case: valid JSON, missing the one field we require.
        return RecognitionEnvelope(
            payload: Data(#"{"schemaVersion": 1, "components": []}"#.utf8),
            providerID: Self.providerID
        )
    }

    private func pause() async {
        guard artificialDelay > .zero else { return }
        try? await Task.sleep(for: artificialDelay)
    }
}
