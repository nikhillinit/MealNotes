import Foundation

/// Injected source of "now", so every time-dependent behaviour (check-in
/// scheduling, evening-meal detection, insights) is deterministic under test.
///
/// Named `DateProvider` rather than `Clock` to avoid colliding with the standard
/// library's `Clock` protocol.
public protocol DateProvider: Sendable {
    func now() -> Date
}

public struct SystemDateProvider: DateProvider {
    public init() {}
    public func now() -> Date { Date() }
}

/// A `DateProvider` that always returns the same instant.
public struct FixedDateProvider: DateProvider {
    public let fixed: Date
    public init(_ fixed: Date) { self.fixed = fixed }
    public func now() -> Date { fixed }
}

public enum CalendarSupport {
    /// A fixed, timezone-stable calendar used for rule review dates and for
    /// building dates in tests. Not used for user-facing formatting.
    public static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    /// Builds a stable date. Used for `lastReviewed` metadata on rules and in tests.
    public static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        guard let date = utc.date(from: components) else {
            preconditionFailure("Invalid fixed date \(year)-\(month)-\(day)")
        }
        return date
    }
}
