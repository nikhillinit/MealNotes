import Foundation

/// A coarse food or drink property that GERD rules can match against.
///
/// Categories are deliberately coarse. They exist so that a deterministic rule
/// can fire without the app having to reason about specific dishes, and so that
/// every warning we show can be traced back to a property somebody actually
/// asserted about the meal.
public enum FoodCategory: String, Codable, Sendable, Hashable, CaseIterable {
    case caffeine
    case chocolate
    case alcohol
    case mint
    case tomato
    case citrus
    case spicy
    case highFat
    case fried
    case carbonated
    case largePortion

    /// Plain dairy. Intentionally **not** matched by any rule on its own — see
    /// ``GERDRuleCatalog`` for the reasoning.
    case dairy

    /// Dairy that is specifically high in fat (cream, full-fat cheese, whole milk).
    case fullFatDairy

    /// Derived from the time of the meal rather than from the photo.
    case lateEvening

    public var displayName: String {
        switch self {
        case .caffeine: "Caffeine"
        case .chocolate: "Chocolate"
        case .alcohol: "Alcohol"
        case .mint: "Mint"
        case .tomato: "Tomato"
        case .citrus: "Citrus"
        case .spicy: "Spicy"
        case .highFat: "High fat"
        case .fried: "Fried"
        case .carbonated: "Fizzy drink"
        case .largePortion: "Large portion"
        case .dairy: "Dairy"
        case .fullFatDairy: "Full-fat dairy"
        case .lateEvening: "Late evening"
        }
    }

    /// Categories the app can ask the user about directly.
    /// `lateEvening` is excluded because it is computed from the clock, not asked.
    public var isUserAnswerable: Bool {
        self != .lateEvening
    }
}
