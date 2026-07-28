import Foundation

public enum CaptureSource: String, Sendable, Hashable, CaseIterable {
    case camera
    case photoLibrary
    /// Milestone 1: a canned image chosen in the app, so the whole flow runs in
    /// the Simulator with no camera and no network.
    case fixture
}

/// One capture, held only for as long as it takes to identify it.
///
/// `data` is transient. Nothing persists it: `MealDraft.retainedPhotoData` is
/// populated only when the user explicitly asks to keep a photo.
public struct CapturedImage: Sendable, Hashable, Identifiable {
    public let id: UUID
    /// Opaque handle passed to recognition. In Milestone 1 this is a fixture name.
    public let identifier: String
    public let data: Data?
    public let source: CaptureSource

    public init(id: UUID = UUID(), identifier: String, data: Data? = nil, source: CaptureSource) {
        self.id = id
        self.identifier = identifier
        self.data = data
        self.source = source
    }
}

public enum CaptureError: Error, Sendable, Equatable {
    case sourceUnavailable(CaptureSource)
    case cancelled
    case unknownIdentifier(String)
}

public protocol CaptureService: Sendable {
    var availableSources: [CaptureSource] { get }
    func capture(identifier: String) async throws -> CapturedImage
}

/// Milestone 1 capture: hands back a named fixture.
public struct FixtureCaptureService: CaptureService {
    public let availableSources: [CaptureSource] = [.fixture]

    public init() {}

    public func capture(identifier: String) async throws -> CapturedImage {
        guard let fixture = RecognitionFixture(rawValue: identifier) else {
            throw CaptureError.unknownIdentifier(identifier)
        }
        return CapturedImage(identifier: fixture.rawValue, data: nil, source: .fixture)
    }
}

/// What was legible on the packaging itself.
public struct ScanFindings: Sendable, Hashable {
    public let barcode: String?
    public let labelText: [String]

    public init(barcode: String? = nil, labelText: [String] = []) {
        self.barcode = barcode
        self.labelText = labelText
    }

    public static let empty = ScanFindings()
}

/// On-device barcode and label reading.
///
/// Phase 2 backs this with VisionKit / Vision. It stays a protocol so the
/// fixture flow can produce the same shape of result without a camera.
public protocol BarcodeAndTextScanner: Sendable {
    func scan(_ image: CapturedImage) async -> ScanFindings
}

/// Returns findings for the packaged-product fixture and nothing for the rest,
/// which is what a real scanner does with a plate of food.
public struct FixtureBarcodeAndTextScanner: BarcodeAndTextScanner {
    public init() {}

    public func scan(_ image: CapturedImage) async -> ScanFindings {
        guard RecognitionFixture(rawValue: image.identifier) == .packagedChocolateBar else {
            return .empty
        }
        return ScanFindings(
            barcode: "7622210449283",
            labelText: ["Sugar", "whole milk powder", "cocoa butter", "cocoa mass"]
        )
    }
}

/// A product record for a scanned barcode.
public struct ProductRecord: Sendable, Hashable {
    public let barcode: String
    public let name: String?
    public let brand: String?
    public let ingredientsText: String?
    public let categories: [FoodCategory]
    /// Required attribution for whichever database the record came from.
    public let attribution: String

    public init(
        barcode: String,
        name: String?,
        brand: String?,
        ingredientsText: String?,
        categories: [FoodCategory],
        attribution: String
    ) {
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.ingredientsText = ingredientsText
        self.categories = categories
        self.attribution = attribution
    }
}

/// Barcode → product lookup.
///
/// The boundary exists in Milestone 1; the integration does not. Phase 2 puts an
/// Open Food Facts client behind this protocol. Until then the app behaves
/// exactly as it must when a lookup finds nothing: it carries on with label text
/// and visual recognition.
public protocol ProductLookupClient: Sendable {
    func product(barcode: String) async throws -> ProductRecord?
}

public struct UnavailableProductLookupClient: ProductLookupClient {
    public init() {}
    public func product(barcode: String) async throws -> ProductRecord? { nil }
}
