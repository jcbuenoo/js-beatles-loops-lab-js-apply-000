import PauseCore
import SwiftUI

/// The panel under the menu bar icon: today at a glance plus shortcuts.
@MainActor
struct MenuView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let _ = state.refreshToken
        let report = state.report(for: Date())
        let unlocks = state.guardian.activeUnlocks

        VStack(alignment: .leading, spacing: 12) {
            Text("Today").font(.headline)
            Text(report.headline)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            CategoryBar(report: report)
                .frame(height: 8)

            HStack(alignment: .top) {
                MiniStat(label: "Active", value: DayReport.format(report.totalActive))
                MiniStat(label: "Distracted", value: DayReport.format(report.seconds(in: .distracting)))
                MiniStat(label: "Urges resisted", value: "\(report.urgesResisted)/\(report.urges.count)")
            }

            if state.settings.guards.isEmpty {
                Text("No guarded apps or sites yet. Add some under Guards & settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !unlocks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(unlocks) { unlock in
                        HStack {
                            Image(systemName: "lock.open")
                            Text("\(unlock.rule.displayName) unlocked")
                            Spacer()
                            Text(unlock.expires, style: .timer)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Button("Lock now") { state.guardian.relock(unlock.rule.id) }
                                .controlSize(.small)
                        }
                        .font(.callout)
                    }
                }
            }

            Divider()

            MenuRow(title: "Log an urge", systemImage: "bolt.heart", shortcut: "⌥⌘U") { state.urgeLogger.show() }
            MenuRow(title: "Where did my day go?", systemImage: "chart.bar.xaxis") { WindowManager.shared.show(.today) }
            MenuRow(title: "Urge log & patterns", systemImage: "list.bullet.rectangle") { WindowManager.shared.show(.urges) }
            MenuRow(title: "Guards & settings", systemImage: "hand.raised") { WindowManager.shared.show(.settings) }

            Divider()

            MenuRow(title: "Quit Pause", systemImage: "power") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 320)
    }
}

private struct MiniStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title3, design: .rounded).weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MenuRow: View {
    let title: String
    let systemImage: String
    var shortcut: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Intentional / neutral / distracting as one stacked bar.
struct CategoryBar: View {
    let report: DayReport

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                if report.totalActive > 0 {
                    ForEach(AppCategory.allCases) { category in
                        let share = report.share(of: category)
                        if share > 0 {
                            Rectangle()
                                .fill(category.color)
                                .frame(width: max(2, geo.size.width * share))
                        }
                    }
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.2))
                }
            }
            .clipShape(Capsule())
        }
    }
}

extension AppCategory {
    var color: Color {
        switch self {
        case .intentional: return .green
        case .neutral: return .gray
        case .distracting: return .orange
        }
    }
}
