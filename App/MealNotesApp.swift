import MealNotesCore
import SwiftUI

@main
struct MealNotesApp: App {
    @State private var environment: AppEnvironment

    init() {
        // UI tests get a fresh, session-only store so they never see, or leave
        // behind, real entries.
        let isUITest = ProcessInfo.processInfo.arguments.contains("--uitest")
        _environment = State(initialValue: AppEnvironment.live(inMemory: isUITest))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
        }
    }
}
