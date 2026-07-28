import MealNotesCore
import SwiftUI

enum Layout {
    /// Apple's minimum, used as a floor everywhere rather than a target.
    static let minimumTouchTarget: CGFloat = 44
    static let primaryActionHeight: CGFloat = 64
    static let cornerRadius: CGFloat = 16
}

/// The one dominant action on a screen.
struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage).imageScale(.large)
                }
                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: Layout.primaryActionHeight)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!isEnabled)
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title).font(.body.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: Layout.minimumTouchTarget)
        }
        .buttonStyle(.bordered)
    }
}

/// A note from the rules engine.
///
/// Concern is carried by the heading, the icon and the words. Colour is only
/// ever a reinforcement, never the message.
struct WarningCard: View {
    let warning: GERDWarning
    var showHeading: Bool = true

    @State private var showingSource = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showHeading {
                Label(warning.heading, systemImage: "exclamationmark.circle.fill")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }

            Text(warning.title)
                .font(.subheadline.weight(.semibold))

            Text(warning.reason)
                .font(.body)

            Text(warning.suggestion)
                .font(.body)
                .foregroundStyle(.secondary)

            DisclosureGroup("Where this comes from", isExpanded: $showingSource) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(warning.sources, id: \.url) { source in
                        Link(source.title, destination: source.url)
                            .font(.footnote)
                    }
                    Text(warning.evidence.displayName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Last checked \(warning.lastReviewed.formatted(date: .abbreviated, time: .omitted))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .font(.footnote)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("result.headsUp.\(warning.ruleID)")
    }
}

/// A calm, non-alarming line for anything that is context rather than guidance.
struct QuietNote: View {
    let text: String
    var systemImage: String = "info.circle"

    var body: some View {
        Label {
            Text(text).font(.footnote)
        } icon: {
            Image(systemName: systemImage)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SeverityBadge: View {
    let severity: CheckInSeverity

    var body: some View {
        Label(severity.displayName, systemImage: severity.symbolName)
            .font(.footnote.weight(.medium))
            .labelStyle(.titleAndIcon)
            .accessibilityLabel("Felt \(severity.displayName)")
    }
}

struct MealRow: View {
    let meal: MealSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meal.displayName)
                .font(.body.weight(.medium))

            HStack(spacing: 8) {
                Text(meal.consumedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let checkIn = meal.checkIn {
                    SeverityBadge(severity: checkIn.severity)
                        .foregroundStyle(.secondary)
                }
            }

            if !meal.shownRuleIDs.isEmpty {
                Text("^[\(meal.shownRuleIDs.count) note](inflect: true) shown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: Layout.minimumTouchTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Wraps a document in a file the share sheet can hand to Mail, Messages or Files.
enum ReportFile {
    static func write(_ document: ExportDocument) -> URL? {
        let url = URL.temporaryDirectory.appending(path: document.filename)
        do {
            try document.data.write(to: url, options: .atomic)
            return url
        } catch {
            AppLog.store.error("Could not write the report: \(error, privacy: .public)")
            return nil
        }
    }
}
