import Foundation

/// "Where did my day go?" — everything the report screen shows, computed from raw spans and urges.
public struct DayReport {
    public struct Row: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let seconds: TimeInterval
        public let category: AppCategory
        public let isWebsite: Bool
    }

    public struct HourSlice: Identifiable, Equatable {
        public var id: String { "\(hour)-\(category.rawValue)" }
        public let hour: Int
        public let category: AppCategory
        public let seconds: TimeInterval
    }

    public let day: Date
    public let totalActive: TimeInterval
    public let rows: [Row]
    public let byCategory: [AppCategory: TimeInterval]
    public let hourly: [HourSlice]
    public let contextSwitches: Int
    public let longestFocus: TimeInterval
    public let urges: [UrgeEntry]

    public var manualUrges: [UrgeEntry] { urges.filter { $0.source == .manual } }
    public var guardEvents: [UrgeEntry] { urges.filter { $0.source.isGuard } }
    public var urgesResisted: Int { urges.filter { $0.outcome == .resisted }.count }
    public var urgesGaveIn: Int { urges.filter { $0.outcome == .gaveIn }.count }
    public var guardsBackedOff: Int { guardEvents.filter { $0.outcome == .resisted }.count }

    public func seconds(in category: AppCategory) -> TimeInterval { byCategory[category] ?? 0 }

    public func share(of category: AppCategory) -> Double {
        totalActive > 0 ? seconds(in: category) / totalActive : 0
    }

    /// One honest sentence (or three) about the day.
    public var headline: String {
        guard totalActive >= 60 else {
            return urges.isEmpty ? "Nothing tracked yet for this day." : "No screen time tracked, but \(urges.count) urge\(urges.count == 1 ? "" : "s") logged."
        }
        var parts = ["Active \(DayReport.format(totalActive))."]
        let distracted = seconds(in: .distracting)
        if distracted >= 60 {
            var s = "Distractions took \(DayReport.format(distracted)) (\(Int((share(of: .distracting) * 100).rounded()))%)"
            if let top = rows.first(where: { $0.category == .distracting }) {
                s += ", mostly \(top.name) (\(DayReport.format(top.seconds)))"
            }
            parts.append(s + ".")
        } else {
            parts.append("Almost no time on distractions.")
        }
        if longestFocus >= 10 * 60 {
            parts.append("Longest focus stretch: \(DayReport.format(longestFocus)).")
        }
        if !urges.isEmpty {
            parts.append("You resisted \(urgesResisted) of \(urges.count) urge\(urges.count == 1 ? "" : "s").")
        }
        return parts.joined(separator: " ")
    }

    public static func build(
        day: Date,
        spans rawSpans: [ActivitySpan],
        urges allUrges: [UrgeEntry],
        categorize: (String) -> AppCategory,
        calendar: Calendar = .current
    ) -> DayReport {
        let dayInterval = calendar.dateInterval(of: .day, for: day) ?? DateInterval(start: day, duration: 86_400)
        let spans = rawSpans.compactMap { $0.clipped(to: dayInterval) }.sorted { $0.start < $1.start }

        var total: TimeInterval = 0
        var perKey: [String: (name: String, seconds: TimeInterval, isWebsite: Bool)] = [:]
        var byCategory: [AppCategory: TimeInterval] = [:]
        var hourly: [Int: [AppCategory: TimeInterval]] = [:]

        for span in spans {
            let category = categorize(span.key)
            total += span.duration
            byCategory[category, default: 0] += span.duration
            var entry = perKey[span.key] ?? (name: span.displayName, seconds: 0, isWebsite: span.domain != nil)
            entry.seconds += span.duration
            perKey[span.key] = entry
            for piece in span.split(by: .hour, calendar: calendar) {
                let hour = calendar.component(.hour, from: piece.start)
                hourly[hour, default: [:]][category, default: 0] += piece.duration
            }
        }

        let rows = perKey.map { key, value in
            Row(id: key, name: value.name, seconds: value.seconds, category: categorize(key), isWebsite: value.isWebsite)
        }
        .sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.name < $1.name }

        let slices = hourly.keys.sorted().flatMap { hour in
            AppCategory.allCases.compactMap { category -> HourSlice? in
                guard let s = hourly[hour]?[category], s > 0 else { return nil }
                return HourSlice(hour: hour, category: category, seconds: s)
            }
        }

        var switches = 0
        for i in spans.indices.dropFirst() where spans[i].key != spans[i - 1].key {
            switches += 1
        }

        let dayUrges = allUrges.filter { dayInterval.contains($0.date) && $0.date < dayInterval.end }
            .sorted { $0.date < $1.date }

        return DayReport(
            day: dayInterval.start,
            totalActive: total,
            rows: rows,
            byCategory: byCategory,
            hourly: slices,
            contextSwitches: switches,
            longestFocus: longestFocusStretch(spans, categorize: categorize),
            urges: dayUrges
        )
    }

    /// Longest run of intentional work. Glances elsewhere under 30 seconds and gaps under a
    /// minute don't break the run (but don't count toward it either).
    static func longestFocusStretch(_ spans: [ActivitySpan], categorize: (String) -> AppCategory) -> TimeInterval {
        var best: TimeInterval = 0
        var run: TimeInterval = 0
        var lastEnd: Date?
        for span in spans {
            if let lastEnd, span.start.timeIntervalSince(lastEnd) > 60 {
                run = 0
            }
            if categorize(span.key) == .intentional {
                run += span.duration
                best = max(best, run)
                lastEnd = span.end
            } else if span.duration >= 30 {
                run = 0
                lastEnd = nil
            }
        }
        return best
    }

    /// 3725 -> "1h 02m", 300 -> "5m", 20 -> "<1m"
    public static func format(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        return String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }
}
