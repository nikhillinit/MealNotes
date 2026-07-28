import Foundation

/// A single claim about one meal: "this contains caffeine", "this does not contain tomato".
///
/// Facts carry their own provenance and confidence so that the rules engine can
/// decide whether a claim is strong enough to justify showing a warning, and so
/// that the exported report can explain why a warning appeared.
public struct FoodFact: Codable, Sendable, Hashable, Identifiable {
    /// Visual guesses below this confidence are not strong enough to warn on.
    /// They become a clarification question instead.
    public static let warrantableVisualConfidence: Double = 0.75

    public let category: FoodCategory
    /// `false` records an explicit absence, e.g. the user answering "no" to
    /// "Was the tea caffeinated?". Absence claims are how a correction cancels
    /// a lower-trust guess.
    public let isPresent: Bool
    public let source: AssertionSource
    /// Clamped to `0...1` on construction.
    public let confidence: Double
    /// Optional human-readable detail, e.g. "black tea".
    public let detail: String?

    public init(
        category: FoodCategory,
        isPresent: Bool = true,
        source: AssertionSource,
        confidence: Double,
        detail: String? = nil
    ) {
        self.category = category
        self.isPresent = isPresent
        self.source = source
        self.confidence = min(max(confidence, 0), 1)
        let trimmed = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.detail = (trimmed?.isEmpty == false) ? trimmed : nil
    }

    public var id: String {
        "\(category.rawValue)|\(source.rawValue)|\(isPresent)|\(detail ?? "")"
    }

    /// A user correction is definitionally certain.
    public static func confirmed(_ category: FoodCategory, isPresent: Bool, detail: String? = nil) -> FoodFact {
        FoodFact(category: category, isPresent: isPresent, source: .userCorrection, confidence: 1, detail: detail)
    }

    /// Whether this claim is strong enough to base a warning on.
    ///
    /// User corrections, label text and barcode records are trusted as stated.
    /// A visual guess has to clear ``warrantableVisualConfidence`` first.
    public var isStrongEnoughToWarn: Bool {
        switch source {
        case .userCorrection, .labelText, .barcodeDatabase:
            true
        case .visualInference:
            confidence >= Self.warrantableVisualConfidence
        }
    }
}
