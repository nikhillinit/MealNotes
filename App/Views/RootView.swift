import MealNotesCore
import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var scan: ScanPresentation?
    @State private var activeCheckIn: CheckInWindowSnapshot?

    enum ScanPresentation: String, Identifiable {
        case withPhoto
        case withoutPhoto
        var id: String { rawValue }
    }

    var body: some View {
        @Bindable var environment = environment

        NavigationStack {
            HomeView(scan: $scan, activeCheckIn: $activeCheckIn)
        }
        .fullScreenCover(item: $scan) { presentation in
            ScanFlowView(startByTyping: presentation == .withoutPhoto)
        }
        .sheet(item: $activeCheckIn) { window in
            CheckInView(window: window)
        }
        .alert(
            environment.urgentAdvisory?.title ?? "",
            isPresented: Binding(
                get: { environment.urgentAdvisory != nil },
                set: { if !$0 { environment.urgentAdvisory = nil } }
            ),
            presenting: environment.urgentAdvisory
        ) { _ in
            Button("OK", role: .cancel) { environment.urgentAdvisory = nil }
        } message: { advisory in
            Text(advisory.message)
        }
        .task { environment.refresh() }
    }
}

struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Binding var scan: RootView.ScanPresentation?
    @Binding var activeCheckIn: CheckInWindowSnapshot?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let window = environment.dueCheckIns.first {
                    pendingCheckIn(window)
                }

                captureActions

                if environment.totalMealCount == 0 {
                    howItWorks
                }

                if !environment.recentMeals.isEmpty {
                    recentMeals
                }

                elsewhere
            }
            .padding()
        }
        .navigationTitle(AppDisclosures.appName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { AboutView() } label: {
                    Label("About this app", systemImage: "info.circle")
                }
                .accessibilityIdentifier("home.about")
            }
        }
        .onAppear { environment.refresh() }
    }

    // MARK: - Sections

    private func pendingCheckIn(_ window: CheckInWindowSnapshot) -> some View {
        Button {
            activeCheckIn = window
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label("How are you feeling?", systemImage: "bell.badge")
                    .font(.headline)
                Text("You have a check-in waiting from \(window.latestMealAt.formatted(date: .omitted, time: .shortened)).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.pendingCheckIn")
        .accessibilityHint("Opens the check-in for your last meal")
    }

    private var captureActions: some View {
        VStack(spacing: 12) {
            Button {
                scan = .withPhoto
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 44))
                    Text("Scan food or drink")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("home.scanButton")
            .accessibilityHint("Takes a photo and works out what it is")

            SecondaryButton(title: "Add without a photo", systemImage: "square.and.pencil") {
                scan = .withoutPhoto
            }
            .accessibilityIdentifier("home.addWithoutPhoto")
        }
    }

    /// Shown only until she has logged something. The half of the loop that is
    /// invisible on a first run is the check-in that comes back later, so it is
    /// the part worth saying out loud.
    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How this works")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text("""
                Take a photo of what you are about to eat or drink. If there is \
                something worth mentioning, you will see a short note before you \
                log it. About two hours later the app asks how you felt. Over \
                time, the answers build up into something you can look back on.
                """)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.howItWorks")
    }

    private var recentMeals: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recently")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(environment.recentMeals) { meal in
                NavigationLink { MealDetailView(meal: meal) } label: { MealRow(meal: meal) }
                    .buttonStyle(.plain)
                Divider()
            }

            if environment.dueCheckIns.isEmpty {
                Button("Check in now") {
                    environment.simulateDueCheckIn()
                }
                .font(.footnote)
                .frame(minHeight: Layout.minimumTouchTarget)
                .accessibilityIdentifier("home.simulateCheckIn")
                .accessibilityHint("Brings your next check-in forward instead of waiting two hours")
            }
        }
    }

    private var elsewhere: some View {
        VStack(spacing: 0) {
            NavigationLink { HistoryView() } label: {
                row(title: "All meals", detail: "\(environment.totalMealCount)", systemImage: "list.bullet")
            }
            .accessibilityIdentifier("home.history")

            Divider()

            NavigationLink { InsightsView() } label: {
                row(title: "Patterns", detail: nil, systemImage: "chart.bar.doc.horizontal")
            }
            .accessibilityIdentifier("home.insights")
        }
        .buttonStyle(.plain)
    }

    private func row(title: String, detail: String?, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if let detail {
                Text(detail).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: Layout.minimumTouchTarget)
        .contentShape(Rectangle())
    }
}

#Preview {
    RootView().environment(AppEnvironment.preview())
}
