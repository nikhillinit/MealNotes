import Foundation

/// Canned recognition payloads used to run the whole app with no network and no
/// credentials.
///
/// They are stored as raw JSON strings on purpose: the fixtures exercise the
/// real decoder, including the defensive paths, rather than handing the app a
/// pre-built Swift value.
public enum RecognitionFixture: String, Sendable, Hashable, CaseIterable, Identifiable {
    case caffeinatedTea
    case salmonWithCouscous
    case tomatoSpicyPasta
    case packagedChocolateBar
    case unknownItem
    case malformedResponse

    // Fixtures below exist to exercise decoder edges. They are not offered in
    // the capture picker.
    case overEagerClarifications
    case unknownCategories
    case hostileStrings

    public var id: String { rawValue }

    /// The fixtures shown in the in-app capture picker.
    public static let demoCases: [RecognitionFixture] = [
        .caffeinatedTea,
        .salmonWithCouscous,
        .tomatoSpicyPasta,
        .packagedChocolateBar,
        .unknownItem,
        .malformedResponse
    ]

    public var title: String {
        switch self {
        case .caffeinatedTea: "Cup of tea"
        case .salmonWithCouscous: "Salmon with couscous"
        case .tomatoSpicyPasta: "Pasta in red sauce"
        case .packagedChocolateBar: "Chocolate bar (barcode)"
        case .unknownItem: "Blurry photo"
        case .malformedResponse: "Recognition failure"
        case .overEagerClarifications: "Too many questions"
        case .unknownCategories: "Unknown categories"
        case .hostileStrings: "Hostile strings"
        }
    }

    public var subtitle: String {
        switch self {
        case .caffeinatedTea: "Asks one question, then a caffeine note"
        case .salmonWithCouscous: "Identified with nothing to flag"
        case .tomatoSpicyPasta: "Tomato note, asks about spice"
        case .packagedChocolateBar: "Details read from the package"
        case .unknownItem: "Not confident — offers manual naming"
        case .malformedResponse: "Falls back to typing a name"
        case .overEagerClarifications: "Decoder caps questions at two"
        case .unknownCategories: "Decoder drops what it does not know"
        case .hostileStrings: "Decoder bounds oversized values"
        }
    }

    public var symbolName: String {
        switch self {
        case .caffeinatedTea: "cup.and.saucer"
        case .salmonWithCouscous: "fork.knife"
        case .tomatoSpicyPasta: "flame"
        case .packagedChocolateBar: "barcode"
        case .unknownItem: "questionmark.circle"
        case .malformedResponse: "exclamationmark.triangle"
        case .overEagerClarifications, .unknownCategories, .hostileStrings: "wrench.and.screwdriver"
        }
    }

    public var payload: Data {
        Data(json.utf8)
    }

    public var json: String {
        switch self {
        case .caffeinatedTea:
            """
            {
              "schemaVersion": 1,
              "proposedName": "Black tea",
              "proposedNameConfidence": 0.82,
              "overallConfidence": 0.78,
              "components": [
                { "name": "Tea in a cup", "confidence": 0.86, "source": "visualInference" }
              ],
              "ingredientCandidates": [
                { "category": "caffeine", "label": "Caffeinated tea", "confidence": 0.55, "source": "visualInference" }
              ],
              "clarifications": [
                { "id": "tea.caffeine", "question": "Was the tea caffeinated?", "category": "caffeine" }
              ],
              "limitations": [
                "A photo cannot show whether a tea is decaffeinated."
              ]
            }
            """

        case .salmonWithCouscous:
            """
            {
              "schemaVersion": 1,
              "proposedName": "Salmon with couscous",
              "proposedNameConfidence": 0.88,
              "overallConfidence": 0.84,
              "components": [
                { "name": "Salmon fillet", "confidence": 0.9, "source": "visualInference" },
                { "name": "Couscous", "confidence": 0.81, "source": "visualInference" },
                { "name": "Green salad", "confidence": 0.64, "source": "visualInference" }
              ],
              "ingredientCandidates": [],
              "clarifications": [],
              "limitations": [
                "Cooking method and added fat are not visible in a photo."
              ]
            }
            """

        case .tomatoSpicyPasta:
            """
            {
              "schemaVersion": 1,
              "proposedName": "Pasta in tomato sauce",
              "proposedNameConfidence": 0.85,
              "overallConfidence": 0.8,
              "components": [
                { "name": "Pasta", "confidence": 0.92, "source": "visualInference" },
                { "name": "Red sauce", "confidence": 0.88, "source": "visualInference" }
              ],
              "ingredientCandidates": [
                { "category": "tomato", "label": "Tomato sauce", "confidence": 0.88, "source": "visualInference" },
                { "category": "spicy", "label": "Chilli", "confidence": 0.52, "source": "visualInference" }
              ],
              "clarifications": [
                { "id": "pasta.spicy", "question": "Did this have a spicy sauce?", "category": "spicy" }
              ],
              "limitations": [
                "Spice level is hard to judge from a photo."
              ]
            }
            """

        case .packagedChocolateBar:
            """
            {
              "schemaVersion": 1,
              "proposedName": "Milk chocolate bar",
              "proposedNameConfidence": 0.97,
              "overallConfidence": 0.95,
              "components": [
                { "name": "Chocolate bar", "confidence": 0.96, "source": "barcodeDatabase" }
              ],
              "ingredientCandidates": [
                { "category": "chocolate", "label": "Cocoa mass and cocoa butter", "confidence": 0.98, "source": "barcodeDatabase" },
                { "category": "dairy", "label": "Milk", "confidence": 0.95, "source": "labelText" },
                { "category": "fullFatDairy", "label": "Whole milk powder", "confidence": 0.93, "source": "labelText" }
              ],
              "clarifications": [],
              "limitations": []
            }
            """

        case .unknownItem:
            """
            {
              "schemaVersion": 1,
              "proposedName": "Mixed dish",
              "proposedNameConfidence": 0.28,
              "overallConfidence": 0.3,
              "components": [],
              "ingredientCandidates": [],
              "clarifications": [],
              "limitations": [
                "The photo was not clear enough to identify this."
              ]
            }
            """

        case .malformedResponse:
            // Deliberately invalid JSON — the payload is cut off mid-object.
            """
            { "schemaVersion": 1, "proposedName": "Some
            """

        case .overEagerClarifications:
            """
            {
              "schemaVersion": 1,
              "proposedName": "Curry with rice",
              "proposedNameConfidence": 0.7,
              "overallConfidence": 0.66,
              "components": [],
              "ingredientCandidates": [
                { "category": "spicy", "label": "Chilli", "confidence": 0.4, "source": "visualInference" }
              ],
              "clarifications": [
                { "id": "q1", "question": "Was this spicy?", "category": "spicy" },
                { "id": "q2", "question": "Did it contain tomato?", "category": "tomato" },
                { "id": "q3", "question": "Was it fried?", "category": "fried" },
                { "id": "q4", "question": "Was it a large portion?", "category": "largePortion" }
              ],
              "limitations": []
            }
            """

        case .unknownCategories:
            """
            {
              "schemaVersion": 1,
              "proposedName": "Bowl of soup",
              "proposedNameConfidence": 0.6,
              "overallConfidence": 0.6,
              "components": [
                { "name": "Broth", "confidence": 0.7, "source": "visualInference" },
                { "confidence": 0.5, "source": "visualInference" }
              ],
              "ingredientCandidates": [
                { "category": "gluten", "label": "Wheat noodles", "confidence": 0.9, "source": "visualInference" },
                { "category": "tomato", "label": "Tomato broth", "confidence": 0.91, "source": "visualInference" },
                { "category": "witchcraft", "label": "???", "confidence": 0.99, "source": "userCorrection" }
              ],
              "clarifications": [
                { "id": "bad", "question": "Was it eaten late?", "category": "lateEvening" }
              ],
              "limitations": []
            }
            """

        case .hostileStrings:
            """
            {
              "schemaVersion": 1,
              "proposedName": "\(String(repeating: "A", count: 400))",
              "proposedNameConfidence": 42.0,
              "overallConfidence": -3.5,
              "components": [
                { "name": "  spaced\\n\\tout  ", "confidence": 2.0, "source": "wishfulThinking" }
              ],
              "ingredientCandidates": [
                { "category": "caffeine", "label": "\(String(repeating: "b", count: 400))", "confidence": 9.9, "source": "visualInference" }
              ],
              "clarifications": [],
              "limitations": ["   ", "A real limitation."]
            }
            """
        }
    }
}
