import Foundation

public enum CheckInAuthorizationStatus: String, Sendable, Hashable {
    case notDetermined
    case authorized
    case provisional
    case denied

    public var canDeliverNotifications: Bool {
        self == .authorized || self == .provisional
    }
}

public struct CheckInNotificationRequest: Sendable, Hashable {
    public let notificationID: String
    public let windowID: UUID
    public let fireDate: Date
    public let title: String
    public let body: String

    public static let defaultTitle = AppDisclosures.appName
    /// The wording from the brief, kept in one place.
    public static let defaultBody = "How are you feeling after your meal?"

    public init(
        notificationID: String,
        windowID: UUID,
        fireDate: Date,
        title: String = CheckInNotificationRequest.defaultTitle,
        body: String = CheckInNotificationRequest.defaultBody
    ) {
        self.notificationID = notificationID
        self.windowID = windowID
        self.fireDate = fireDate
        self.title = title
        self.body = body
    }
}

/// Schedules the "how are you feeling?" reminder.
///
/// Scheduling never throws. A notification is a convenience: the pending
/// check-in also lives in the database and is shown in the app, so a denied
/// permission degrades the experience without breaking it.
public protocol CheckInScheduler: Sendable {
    func currentAuthorization() async -> CheckInAuthorizationStatus
    @discardableResult
    func requestAuthorization() async -> CheckInAuthorizationStatus
    func schedule(_ request: CheckInNotificationRequest) async
    func cancel(notificationID: String) async
    func pendingNotificationIDs() async -> [String]
}

/// In-memory scheduler used by tests, previews and the Simulator.
public actor InMemoryCheckInScheduler: CheckInScheduler {
    public private(set) var scheduled: [CheckInNotificationRequest] = []
    public private(set) var cancelledIDs: [String] = []
    private var authorization: CheckInAuthorizationStatus

    public init(authorization: CheckInAuthorizationStatus = .authorized) {
        self.authorization = authorization
    }

    public func currentAuthorization() async -> CheckInAuthorizationStatus { authorization }

    @discardableResult
    public func requestAuthorization() async -> CheckInAuthorizationStatus {
        if authorization == .notDetermined { authorization = .authorized }
        return authorization
    }

    public func schedule(_ request: CheckInNotificationRequest) async {
        scheduled.removeAll { $0.notificationID == request.notificationID }
        scheduled.append(request)
    }

    public func cancel(notificationID: String) async {
        cancelledIDs.append(notificationID)
        scheduled.removeAll { $0.notificationID == notificationID }
    }

    public func pendingNotificationIDs() async -> [String] {
        scheduled.map(\.notificationID)
    }
}
