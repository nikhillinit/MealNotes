import Foundation
import MealNotesCore
import OSLog
import SwiftData

enum AppLog {
    static let subsystem = "ai.narralytics.MealNotes"
    static let flow = Logger(subsystem: subsystem, category: "flow")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
}

/// Everything the views need, assembled in one place.
///
/// Views reach for services through this object rather than constructing them,
/// so the whole app can be run against fixtures, previews or a test store by
/// building a different environment.
@MainActor
@Observable
final class AppEnvironment {
    // Services
    let repository: any MealRepository
    let mealLogger: MealLogger
    let rulesEngine: GERDRulesEngine
    let insightEngine: InsightEngine
    let captureService: any CaptureService
    let scanner: any BarcodeAndTextScanner
    let productLookup: any ProductLookupClient
    let recognition: RecognitionCoordinator
    let scheduler: any CheckInScheduler
    let dates: any DateProvider

    // Observed state
    private(set) var recentMeals: [MealSnapshot] = []
    private(set) var dueCheckIns: [CheckInWindowSnapshot] = []
    private(set) var insights: [Insight] = []
    private(set) var totalMealCount: Int = 0

    /// Set when the last action produced something worth saying out loud.
    var urgentAdvisory: UrgentAdvisory?

    init(
        repository: any MealRepository,
        scheduler: any CheckInScheduler,
        recognitionClient: any RecognitionClient,
        captureService: any CaptureService = FixtureCaptureService(),
        scanner: any BarcodeAndTextScanner = FixtureBarcodeAndTextScanner(),
        productLookup: any ProductLookupClient = UnavailableProductLookupClient(),
        rulesEngine: GERDRulesEngine = GERDRulesEngine(),
        insightEngine: InsightEngine = InsightEngine(),
        dates: any DateProvider = SystemDateProvider()
    ) {
        self.repository = repository
        self.scheduler = scheduler
        self.captureService = captureService
        self.scanner = scanner
        self.productLookup = productLookup
        self.rulesEngine = rulesEngine
        self.insightEngine = insightEngine
        self.dates = dates
        self.recognition = RecognitionCoordinator(client: recognitionClient)
        self.mealLogger = MealLogger(repository: repository, scheduler: scheduler)
    }

    /// The app as it ships in Milestone 1: local store, fixture recognition,
    /// real local notifications.
    static func live(inMemory: Bool = false) -> AppEnvironment {
        let container: ModelContainer
        do {
            container = inMemory
                ? try MealNotesSchema.inMemoryContainer()
                : try MealNotesSchema.onDiskContainer()
        } catch {
            // A journal that cannot open its store is still better than a crash:
            // fall back to a session-only store and say so in the log.
            AppLog.store.error("Could not open the store, using a temporary one: \(error, privacy: .public)")
            container = try! MealNotesSchema.inMemoryContainer()
        }

        return AppEnvironment(
            repository: SwiftDataMealRepository(container: container),
            scheduler: UserNotificationsCheckInScheduler(),
            // A small delay so the identifying state is visible rather than a flash.
            recognitionClient: MockRecognitionClient(artificialDelay: .milliseconds(450))
        )
    }

    static func preview() -> AppEnvironment {
        AppEnvironment(
            repository: SwiftDataMealRepository(container: try! MealNotesSchema.inMemoryContainer()),
            scheduler: InMemoryCheckInScheduler(),
            recognitionClient: MockRecognitionClient()
        )
    }

    // MARK: - State

    func refresh() {
        do {
            let all = try repository.allMeals()
            totalMealCount = all.count
            recentMeals = Array(all.prefix(5))
            dueCheckIns = try repository.dueWindows(asOf: dates.now())
            insights = insightEngine.insights(from: all)
        } catch {
            AppLog.store.error("Refresh failed: \(error, privacy: .public)")
        }
    }

    func allMeals() -> [MealSnapshot] {
        (try? repository.allMeals()) ?? []
    }

    func meals(withIDs ids: [UUID]) -> [MealSnapshot] {
        (try? repository.meals(withIDs: ids)) ?? []
    }

    func personalNote(for categories: Set<FoodCategory>) -> String? {
        insightEngine.personalNote(for: categories, meals: allMeals())
    }

    // MARK: - Check-ins

    func recordCheckIn(
        windowID: UUID,
        severity: CheckInSeverity,
        symptoms: [SymptomTag],
        urgentSymptoms: [UrgentSymptom]
    ) async {
        do {
            urgentAdvisory = try await mealLogger.recordCheckIn(
                windowID: windowID,
                severity: severity,
                symptoms: symptoms,
                urgentSymptoms: urgentSymptoms,
                at: dates.now()
            )
        } catch {
            AppLog.store.error("Could not record check-in: \(error, privacy: .public)")
        }
        refresh()
    }

    /// Brings the most recent pending check-in forward so the flow can be tried
    /// without waiting two hours. Exposed in the app because Milestone 1 has to
    /// be demonstrable end to end in one sitting.
    func simulateDueCheckIn() {
        let now = dates.now()
        do {
            let candidates = try repository.openWindows(asOf: now)
                .sorted { $0.latestMealAt > $1.latestMealAt }
            guard let window = candidates.first else { return }
            try repository.extendWindow(
                id: window.id,
                latestMealAt: window.latestMealAt,
                fireDate: now.addingTimeInterval(-1)
            )
            Task { await scheduler.cancel(notificationID: window.notificationID) }
        } catch {
            AppLog.store.error("Could not bring a check-in forward: \(error, privacy: .public)")
        }
        refresh()
    }

    func requestNotificationPermissionIfNeeded() async {
        let status = await scheduler.currentAuthorization()
        guard status == .notDetermined else { return }
        let granted = await scheduler.requestAuthorization()
        AppLog.notifications.info("Notification permission: \(granted.rawValue, privacy: .public)")
    }
}
