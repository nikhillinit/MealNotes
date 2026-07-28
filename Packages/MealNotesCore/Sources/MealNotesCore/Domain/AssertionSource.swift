import Foundation

/// Where a claim about a meal came from.
///
/// The order of `trustRank` is the information-precedence contract for the whole
/// app: a lower-trust source must never silently replace a higher-trust one.
public enum AssertionSource: String, Codable, Sendable, Hashable, CaseIterable, Comparable {
    /// Something the user typed, confirmed, or corrected. Highest trust.
    case userCorrection
    /// Ingredient or nutrition text read off the physical package.
    case labelText
    /// A product record looked up from a barcode.
    case barcodeDatabase
    /// A guess made from the pixels. Lowest trust.
    case visualInference

    public var trustRank: Int {
        switch self {
        case .userCorrection: 4
        case .labelText: 3
        case .barcodeDatabase: 2
        case .visualInference: 1
        }
    }

    public var displayName: String {
        switch self {
        case .userCorrection: "You confirmed this"
        case .labelText: "Read from the label"
        case .barcodeDatabase: "From the product barcode"
        case .visualInference: "Guessed from the photo"
        }
    }

    public static func < (lhs: AssertionSource, rhs: AssertionSource) -> Bool {
        lhs.trustRank < rhs.trustRank
    }
}
