import Charts
import PauseCore
import SwiftUI

/// Every urge you've logged or met at a guard, plus the patterns in them.
@MainActor
struct UrgeLogView: View {
    @EnvironmentObject private var state: AppState
    @State private var range: Range = .week
    @State private var filter: Filter = .all

    enum Range: String, CaseIterable, Identifiable {
        case week = "7 days"
        case month = "30 days"
        case all = "All time"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .week: return 7
            case .month: return 30
            case .all: return nil
            }
        }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Everything"
        case manual = "Logged by me"
        case guards = "Guard screens"
        var id: String { rawValue }
    }

    private var urgesInRange: [UrgeEntry] {
        guard let days = range.days,
              let start = state.calendar.date(byAdding: .day, value: -(days - 1), to: state.calendar.startOfDay(for: Date()))
        else { return state.urges }
        return state.urges.filter { $0.date >= start }
    }

    private var visible: [UrgeEntry] {
        urgesInRange.filter { urge in
            switch filter {
            case .all: return true
            case .manual: return urge.source == .manual
            case .guards: return urge.source.isGuard
            }
        }
        .sorted { $0.date > $1.date }
    }

    var body: some View {
        let insights = UrgeInsights.build(urgesInRange, calendar: state.calendar)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Picker("Range", selection: $range) {
                        ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 280)
                    Spacer()
                    Button {
                        state.urgeLogger.show()
                    } label: {
                        Label("Log an urge", systemImage: "plus")
                    }
                }

                if insights.total == 0 {
                    Text("No urges logged in this period. Press ⌥⌘U the next time you feel the pull to do something you didn't plan to. Logging it is enough.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    insightsSection(insights)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Log").font(.headline)
                        Spacer()
                        Picker("Show", selection: $filter) {
                            ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .frame(width: 200)
                    }
                    ForEach(visible) { urge in
                        UrgeLogRow(urge: urge, calendar: state.calendar) { outcome in
                            state.setOutcome(outcome, for: urge.id)
                        } onDelete: {
                            state.deleteUrge(urge.id)
                        }
                        Divider()
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 600, minHeight: 520)
    }

    @ViewBuilder
    private func insightsSection(_ insights: UrgeInsights) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            StatTile(label: "Urges", value: "\(insights.total)")
            StatTile(label: "Resisted", value: "\(Int((insights.resistRate * 100).rounded()))%", tint: .green)
            StatTile(label: "Average strength", value: String(format: "%.1f / 5", insights.averageIntensity))
            StatTile(label: "Peak hour", value: insights.peakHour.map { HourlyChart.hourLabel($0) } ?? "–")
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("When urges hit").font(.headline)
            Chart(Array(insights.byHour.enumerated()), id: \.offset) { item in
                BarMark(x: .value("Hour", item.offset), y: .value("Urges", item.element))
                    .foregroundStyle(Color.purple.gradient)
            }
            .chartXScale(domain: -1...24)
            .chartXAxis {
                AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hour = value.as(Int.self) { Text(HourlyChart.hourLabel(hour)) }
                    }
                }
            }
            .frame(height: 150)
        }

        HStack(alignment: .top, spacing: 24) {
            CountList(title: "Most common", items: insights.topTargets)
            CountList(title: "Usually while in", items: insights.topContexts)
        }
    }
}

private struct CountList: View {
    let title: String
    let items: [UrgeInsights.Count]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if items.isEmpty {
                Text("–").foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                HStack {
                    Text(item.name).lineLimit(1)
                    Spacer()
                    Text("\(item.count)").monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UrgeLogRow: View {
    let urge: UrgeEntry
    let calendar: Calendar
    let onOutcome: (UrgeOutcome) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(urge.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .monospacedDigit()
                Text(sourceLabel).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 110, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(urge.text)
                if let context = urge.context {
                    Text(context).font(.caption).foregroundStyle(.secondary)
                }
                Text(String(repeating: "●", count: urge.intensity) + String(repeating: "○", count: 5 - urge.intensity))
                    .font(.caption2)
                    .foregroundStyle(.purple)
            }
            Spacer()
            Picker("Outcome", selection: Binding(get: { urge.outcome }, set: onOutcome)) {
                ForEach(UrgeOutcome.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 140)
        }
        .contextMenu {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private var sourceLabel: String {
        switch urge.source {
        case .manual: return "logged"
        case .speedBump:
            return urge.unlockedMinutes.map { "speed bump · opened \($0)m" } ?? "speed bump · walked away"
        case .block:
            return urge.unlockedMinutes.map { "block · unlocked \($0)m" } ?? "block · walked away"
        }
    }
}
