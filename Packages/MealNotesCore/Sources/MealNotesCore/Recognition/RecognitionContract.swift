import Foundation

/// Hard limits applied while decoding a recognition payload.
///
/// These are a safety boundary, not a style preference: the payload is untrusted
/// input, so it is bounded before anything else in the app sees it.
public enum RecognitionLimits {
    public static let supportedSchemaVersion = 1
    /// The product contract: never more than two questions after a capture.
    public static let maxClarificationQuestions = 2
    public static let maxComponents = 12
    public static let maxIngredientCandidates = 16
    public static let maxLimitations = 4
    public static let maxStringLength = 160
    public static let maxPayloadBytes = 64 * 1024
}

public enum RecognitionError: Error, Sendable, Equatable {
    case malformed(String)
    case unsupportedSchemaVersion(found: Int)
    case payloadTooLarge(bytes: Int)
    case serviceUnavailable

    public var shortReason: String {
        switch self {
        case .malformed(let detail): "Malformed response: \(detail)"
        case .unsupportedSchemaVersion(let found): "Unsupported schema version \(found)"
        case .payloadTooLarge(let bytes): "Response too large (\(bytes) bytes)"
        case .serviceUnavailable: "Recognition is unavailable"
        }
    }
}

/// Trims, collapses and bounds untrusted strings and numbers.
enum RecognitionSanitizer {
    /// Control characters and newlines become spaces rather than vanishing, so
    /// "spaced\n\tout" reads as two words instead of running together.
    static func text(_ raw: String, limit: Int = RecognitionLimits.maxStringLength) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            let isSeparator = CharacterSet.controlCharacters.contains(scalar)
                || CharacterSet.whitespacesAndNewlines.contains(scalar)
            scalars.append(isSeparator ? " " : scalar)
        }
        let collapsed = String(scalars)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return String(collapsed.prefix(limit))
    }

    static func confidence(_ raw: Double?) -> Double {
        guard let raw, raw.isFinite else { return 0 }
        return min(max(raw, 0), 1)
    }
}

/// Decodes each element independently so one bad entry cannot discard the array.
private struct Failable<Wrapped: Decodable>: Decodable {
    let value: Wrapped?
    init(from decoder: any Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

private extension KeyedDecodingContainer {
    /// Decodes an array, dropping (and counting) elements that fail to decode.
    func lossyArray<Element: Decodable>(
        _ type: Element.Type,
        forKey key: Key,
        limit: Int
    ) -> (elements: [Element], dropped: Int) {
        guard let raw = try? decode([Failable<Element>].self, forKey: key) else {
            return ([], 0)
        }
        let decoded = raw.compactMap(\.value)
        let dropped = raw.count - decoded.count
        if decoded.count > limit {
            return (Array(decoded.prefix(limit)), dropped + (decoded.count - limit))
        }
        return (decoded, dropped)
    }
}

/// One thing the recogniser believes it can see in the picture.
public struct RecognizedComponent: Codable, Sendable, Hashable {
    public let name: String
    public let confidence: Double
    public let source: AssertionSource

    public init(name: String, confidence: Double, source: AssertionSource) {
        self.name = RecognitionSanitizer.text(name)
        self.confidence = RecognitionSanitizer.confidence(confidence)
        self.source = source
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = RecognitionSanitizer.text(try container.decode(String.self, forKey: .name))
        guard !name.isEmpty else {
            throw RecognitionError.malformed("component with empty name")
        }
        self.name = name
        self.confidence = RecognitionSanitizer.confidence(try? container.decode(Double.self, forKey: .confidence))
        self.source = (try? container.decode(AssertionSource.self, forKey: .source)) ?? .visualInference
    }
}

/// A proposed ingredient or category, with where the claim came from.
public struct IngredientCandidate: Codable, Sendable, Hashable {
    public let category: FoodCategory
    public let label: String
    public let confidence: Double
    public let source: AssertionSource

    public init(category: FoodCategory, label: String, confidence: Double, source: AssertionSource) {
        self.category = category
        self.label = RecognitionSanitizer.text(label)
        self.confidence = RecognitionSanitizer.confidence(confidence)
        self.source = source
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // An unknown category is dropped rather than guessed at.
        self.category = try container.decode(FoodCategory.self, forKey: .category)
        self.label = RecognitionSanitizer.text((try? container.decode(String.self, forKey: .label)) ?? "")
        self.confidence = RecognitionSanitizer.confidence(try? container.decode(Double.self, forKey: .confidence))
        self.source = (try? container.decode(AssertionSource.self, forKey: .source)) ?? .visualInference
    }

    /// The candidate expressed as a fact the rules engine can reason about.
    public var fact: FoodFact {
        FoodFact(
            category: category,
            isPresent: true,
            source: source,
            confidence: confidence,
            detail: label.isEmpty ? nil : label
        )
    }
}

/// A single yes/no question the app may ask before showing a warning.
public struct ClarificationQuestion: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let question: String
    public let category: FoodCategory
    public let detail: String?

    public init(id: String, question: String, category: FoodCategory, detail: String? = nil) {
        let cleanID = RecognitionSanitizer.text(id, limit: 64)
        self.id = cleanID.isEmpty ? "clarify.\(category.rawValue)" : cleanID
        self.question = RecognitionSanitizer.text(question)
        self.category = category
        self.detail = detail.map { RecognitionSanitizer.text($0) }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let category = try container.decode(FoodCategory.self, forKey: .category)
        let question = RecognitionSanitizer.text(try container.decode(String.self, forKey: .question))
        guard !question.isEmpty else {
            throw RecognitionError.malformed("clarification with empty question")
        }
        guard category.isUserAnswerable else {
            throw RecognitionError.malformed("clarification for a category the user cannot answer")
        }
        let rawID = RecognitionSanitizer.text((try? container.decode(String.self, forKey: .id)) ?? "", limit: 64)
        self.id = rawID.isEmpty ? "clarify.\(category.rawValue)" : rawID
        self.question = question
        self.category = category
        let detail = RecognitionSanitizer.text((try? container.decode(String.self, forKey: .detail)) ?? "")
        self.detail = detail.isEmpty ? nil : detail
    }

    /// The fact recorded when the user answers.
    public func answer(_ isPresent: Bool) -> FoodFact {
        FoodFact.confirmed(category, isPresent: isPresent, detail: detail)
    }
}

/// The strict response contract for visual recognition.
///
/// Every field is bounded and sanitised while decoding. A payload that cannot be
/// made sense of throws rather than producing a half-populated value.
public struct RecognitionResponse: Codable, Sendable, Hashable {
    public let schemaVersion: Int
    public let proposedName: String
    public let proposedNameConfidence: Double
    public let overallConfidence: Double
    public let components: [RecognizedComponent]
    public let ingredientCandidates: [IngredientCandidate]
    public let clarifications: [ClarificationQuestion]
    public let limitations: [String]
    /// Records anything defensive decoding had to drop or truncate. Surfaced in
    /// the meal's provenance rather than to the user.
    public let decodingNotes: [String]

    public init(
        proposedName: String,
        proposedNameConfidence: Double,
        overallConfidence: Double,
        components: [RecognizedComponent] = [],
        ingredientCandidates: [IngredientCandidate] = [],
        clarifications: [ClarificationQuestion] = [],
        limitations: [String] = [],
        decodingNotes: [String] = []
    ) {
        self.schemaVersion = RecognitionLimits.supportedSchemaVersion
        self.proposedName = RecognitionSanitizer.text(proposedName)
        self.proposedNameConfidence = RecognitionSanitizer.confidence(proposedNameConfidence)
        self.overallConfidence = RecognitionSanitizer.confidence(overallConfidence)
        self.components = Array(components.prefix(RecognitionLimits.maxComponents))
        self.ingredientCandidates = Array(ingredientCandidates.prefix(RecognitionLimits.maxIngredientCandidates))
        self.clarifications = Array(clarifications.prefix(RecognitionLimits.maxClarificationQuestions))
        self.limitations = Array(limitations.prefix(RecognitionLimits.maxLimitations))
        self.decodingNotes = decodingNotes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var notes: [String] = []

        let version = (try? container.decode(Int.self, forKey: .schemaVersion))
            ?? RecognitionLimits.supportedSchemaVersion
        guard version == RecognitionLimits.supportedSchemaVersion else {
            throw RecognitionError.unsupportedSchemaVersion(found: version)
        }
        self.schemaVersion = version

        guard let rawName = try? container.decode(String.self, forKey: .proposedName) else {
            throw RecognitionError.malformed("proposedName missing or not a string")
        }
        let name = RecognitionSanitizer.text(rawName)
        guard !name.isEmpty else {
            throw RecognitionError.malformed("proposedName was empty after sanitising")
        }
        if name.count < rawName.trimmingCharacters(in: .whitespacesAndNewlines).count {
            notes.append("proposedName truncated to \(RecognitionLimits.maxStringLength) characters")
        }
        self.proposedName = name

        self.proposedNameConfidence = RecognitionSanitizer.confidence(
            try? container.decode(Double.self, forKey: .proposedNameConfidence)
        )
        self.overallConfidence = RecognitionSanitizer.confidence(
            try? container.decode(Double.self, forKey: .overallConfidence)
        )

        let componentResult = container.lossyArray(
            RecognizedComponent.self, forKey: .components, limit: RecognitionLimits.maxComponents
        )
        self.components = componentResult.elements
        if componentResult.dropped > 0 {
            notes.append("dropped \(componentResult.dropped) component(s)")
        }

        let ingredientResult = container.lossyArray(
            IngredientCandidate.self, forKey: .ingredientCandidates, limit: RecognitionLimits.maxIngredientCandidates
        )
        self.ingredientCandidates = ingredientResult.elements
        if ingredientResult.dropped > 0 {
            notes.append("dropped \(ingredientResult.dropped) ingredient candidate(s)")
        }

        // Ask at most two questions no matter what the payload requests.
        let clarificationResult = container.lossyArray(
            ClarificationQuestion.self, forKey: .clarifications, limit: RecognitionLimits.maxClarificationQuestions
        )
        self.clarifications = clarificationResult.elements
        if clarificationResult.dropped > 0 {
            notes.append("dropped \(clarificationResult.dropped) clarification(s)")
        }

        let rawLimitations = (try? container.decode([String].self, forKey: .limitations)) ?? []
        self.limitations = Array(
            rawLimitations.map { RecognitionSanitizer.text($0) }
                .filter { !$0.isEmpty }
                .prefix(RecognitionLimits.maxLimitations)
        )

        self.decodingNotes = notes
    }

    /// Candidate facts, before information precedence is applied.
    public var candidateFacts: [FoodFact] {
        ingredientCandidates.map(\.fact)
    }
}

/// Turns raw bytes into a validated ``RecognitionResponse``.
public struct RecognitionResponseDecoder: Sendable {
    public init() {}

    public func decode(_ data: Data) throws -> RecognitionResponse {
        guard data.count <= RecognitionLimits.maxPayloadBytes else {
            throw RecognitionError.payloadTooLarge(bytes: data.count)
        }
        do {
            return try JSONDecoder().decode(RecognitionResponse.self, from: data)
        } catch let error as RecognitionError {
            throw error
        } catch let error as DecodingError {
            throw RecognitionError.malformed(Self.describe(error))
        } catch {
            throw RecognitionError.malformed("unreadable payload")
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted: "payload is not valid JSON"
        case .keyNotFound(let key, _): "missing key '\(key.stringValue)'"
        case .typeMismatch(let type, _): "wrong type for \(type)"
        case .valueNotFound(let type, _): "missing value for \(type)"
        @unknown default: "could not decode payload"
        }
    }
}
