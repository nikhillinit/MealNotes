import MealNotesCore
import SwiftUI
import UIKit

struct AboutView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        List {
            Section("What this is") {
                Text(AppDisclosures.notMedicalCare)
            }

            Section("When to speak to someone") {
                Text(AppDisclosures.whenToSeekHelp)
            }

            Section("Where the notes come from") {
                Text(AppDisclosures.howWarningsWork)
                ForEach(uniqueSources, id: \.url) { source in
                    Link(source.title, destination: source.url)
                        .frame(minHeight: Layout.minimumTouchTarget)
                }
            }

            Section("Your information") {
                Text(AppDisclosures.privacySummary)
            }

            Section {
                NavigationLink("See every note the app can show") { RuleListView() }
                    .frame(minHeight: Layout.minimumTouchTarget)
            }

            Section {
                ExportMenu()
            } header: {
                Text("Share a record")
            } footer: {
                Text("Sends a copy of your entries using the normal iPhone share sheet.")
            }

            Section {
                Button("Bring my next check-in forward") {
                    environment.simulateDueCheckIn()
                }
                .frame(minHeight: Layout.minimumTouchTarget)
                .accessibilityIdentifier("about.simulateCheckIn")
            } header: {
                Text("Trying the app out")
            } footer: {
                Text("Moves the next check-in to now, so the flow can be tried without waiting two hours.")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var uniqueSources: [RuleSource] {
        var seen: Set<URL> = []
        return environment.rulesEngine.rules
            .flatMap(\.sources)
            .filter { seen.insert($0.url).inserted }
    }
}

struct RuleListView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        List(environment.rulesEngine.rules) { rule in
            VStack(alignment: .leading, spacing: 6) {
                Text(rule.title).font(.body.weight(.medium))
                Text(rule.explanation).font(.footnote)
                Text(rule.suggestion).font(.footnote).foregroundStyle(.secondary)
                Text(rule.evidence.displayName).font(.caption).foregroundStyle(.secondary)
                ForEach(rule.sources, id: \.url) { source in
                    Link(source.title, destination: source.url).font(.caption)
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Every note")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Export

struct ShareableFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ExportMenu: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var share: ShareableFile?
    @State private var failed = false

    var body: some View {
        Menu {
            Button(ExportFormat.plainText.displayName) {
                present(PlainTextReportExporter())
            }
            .accessibilityIdentifier("export.plainText")

            Button(ExportFormat.csv.displayName) {
                present(CSVReportExporter())
            }
            .accessibilityIdentifier("export.csv")
        } label: {
            Label("Share a report", systemImage: "square.and.arrow.up")
                .frame(minHeight: Layout.minimumTouchTarget)
        }
        .accessibilityIdentifier("export.menu")
        .sheet(item: $share) { file in
            ActivityView(url: file.url)
        }
        .alert("The report could not be prepared", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func present(_ exporter: any ReportExporter) {
        let document = exporter.export(meals: environment.allMeals(), generatedAt: environment.dates.now())
        if let url = ReportFile.write(document) {
            share = ShareableFile(url: url)
        } else {
            failed = true
        }
    }
}

/// The system share sheet.
struct ActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
