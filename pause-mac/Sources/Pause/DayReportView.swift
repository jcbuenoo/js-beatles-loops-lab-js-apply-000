import Charts
import PauseCore
import SwiftUI

/// "Where did my day go?" — an honest look at one day.
@MainActor
struct DayReportView: View {
    @EnvironmentObject private var state: AppState
    @State private var day = Date()

    private var isToday: Bool { state.calendar.isDateInToday(day) }

    var body: some View {
        let _ = state.refreshToken
        let report = state.report(for: day)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                Text(report.headline)
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    StatTile(label: "Active", value: DayReport.format(report.totalActive))
                    StatTile(label: "Intentional", value: DayReport.format(report.seconds(in: .intentional)), tint: .green)
                    StatTile(label: "Distracting", value: DayReport.format(report.seconds(in: .distracting)), tint: .orange)
                    StatTile(label: "Longest focus", value: DayReport.format(report.longestFocus))
                    StatTile(label: "App/site switches", value: "\(report.contextSwitches)")
                    StatTile(label: "Urges resisted", value: "\(report.urgesResisted) of \(report.urges.count)")
                    StatTile(label: "Walked away at a guard", value: "\(report.guardsBackedOff) of \(report.guardEvents.count)")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Through the day").font(.headline)
                    CategoryBar(report: report).frame(height: 10)
                    HourlyChart(report: report)
                        .frame(height: 190)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Where it went").font(.headline)
                    Text("Click a label to change it. Pause remembers your choice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if report.rows.isEmpty {
                        Text("Nothing recorded for this day.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                    let top = report.rows.first?.seconds ?? 1
                    ForEach(report.rows.prefix(30)) { row in
                        UsageRow(row: row, fraction: row.seconds / max(top, 1)) { category in
                            state.setCategory(category, for: row.id)
                        }
                    }
                }

                if !report.urges.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Urges and guard screens").font(.headline)
                        ForEach(report.urges) { urge in
                            UrgeRow(urge: urge)
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 560, minHeight: 520)
    }

    private var header: some View {
        HStack {
            Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
            Text(day, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.title2.weight(.semibold))
                .frame(minWidth: 220)
            Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                .disabled(isToday)
            Spacer()
            if !isToday {
                Button("Today") { day = Date() }
            }
        }
    }

    private func shiftDay(_ delta: Int) {
        if let d = state.calendar.date(byAdding: .day, value: delta, to: day) { day = d }
    }
}

struct HourlyChart: View {
    let report: DayReport

    var body: some View {
        Chart(report.hourly) { slice in
            BarMark(
                x: .value("Hour", slice.hour),
                y: .value("Minutes", slice.seconds / 60)
            )
            .foregroundStyle(by: .value("Type", slice.category.label))
        }
        .chartForegroundStyleScale([
            AppCategory.intentional.label: AppCategory.intentional.color,
            AppCategory.neutral.label: AppCategory.neutral.color,
            AppCategory.distracting.label: AppCategory.distracting.color,
        ])
        .chartXScale(domain: -1...24)
        .chartXAxis {
            AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hour = value.as(Int.self) { Text(Self.hourLabel(hour)) }
                }
            }
        }
        .chartYAxisLabel("minutes")
    }

    static func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return "12a"
        case 12: return "12p"
        default: return hour < 12 ? "\(hour)a" : "\(hour - 12)p"
        }
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }
}

struct UsageRow: View {
    let row: DayReport.Row
    let fraction: Double
    let onCategory: (AppCategory) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: row.isWebsite ? "globe" : "app")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(row.name)
                .lineLimit(1)
                .frame(width: 190, alignment: .leading)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(row.category.color.opacity(0.75))
                    .frame(width: max(3, geo.size.width * fraction), height: 10)
                    .frame(maxHeight: .infinity)
            }
            .frame(height: 18)
            Text(DayReport.format(row.seconds))
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
            Menu {
                ForEach(AppCategory.allCases) { category in
                    Button(category.label) { onCategory(category) }
                }
            } label: {
                Text(row.category.label)
                    .font(.caption)
                    .foregroundStyle(row.category.color)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(width: 96, alignment: .trailing)
        }
    }
}

struct UrgeRow: View {
    let urge: UrgeEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(urge.date, format: .dateTime.hour().minute())
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Image(systemName: icon)
                .foregroundStyle(urge.outcome == .resisted ? Color.green : (urge.outcome == .gaveIn ? Color.orange : Color.secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let context = urge.context {
                    Text(context).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(urge.outcome.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var icon: String {
        switch urge.source {
        case .manual: return "bolt.heart"
        case .speedBump: return "pause.circle"
        case .block: return "hand.raised"
        }
    }

    private var title: String {
        guard urge.source.isGuard else { return urge.text }
        let name = urge.targetName ?? urge.target ?? "a guarded app"
        if let minutes = urge.unlockedMinutes {
            return "Opened \(name) for \(minutes) min: “\(urge.text)”"
        }
        return "Walked away from \(name)"
    }
}
