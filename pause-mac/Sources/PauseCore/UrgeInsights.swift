import Foundation

/// Patterns across logged urges: when they hit, what they're about, and how often you win.
public struct UrgeInsights {
    public struct Count: Identifiable, Equatable {
        public var id: String { name }
        public let name: String
        public let count: Int
    }

    public let total: Int
    public let resisted: Int
    public let gaveIn: Int
    public let undecided: Int
    /// Index 0…23.
    public let byHour: [Int]
    /// Index 0…6 = Sunday…Saturday.
    public let byWeekday: [Int]
    public let topTargets: [Count]
    public let topContexts: [Count]
    public let averageIntensity: Double

    /// Share of decided urges you resisted (ignores "still deciding").
    public var resistRate: Double {
        let decided = resisted + gaveIn
        return decided > 0 ? Double(resisted) / Double(decided) : 0
    }

    public var peakHour: Int? {
        guard let max = byHour.max(), max > 0 else { return nil }
        return byHour.firstIndex(of: max)
    }

    public static func build(_ urges: [UrgeEntry], calendar: Calendar = .current) -> UrgeInsights {
        var byHour = Array(repeating: 0, count: 24)
        var byWeekday = Array(repeating: 0, count: 7)
        var targets: [String: Int] = [:]
        var contexts: [String: Int] = [:]
        var intensity = 0

        for u in urges {
            byHour[calendar.component(.hour, from: u.date)] += 1
            byWeekday[calendar.component(.weekday, from: u.date) - 1] += 1
            targets[topic(of: u), default: 0] += 1
            if let c = u.context, !c.isEmpty { contexts[c, default: 0] += 1 }
            intensity += u.intensity
        }

        return UrgeInsights(
            total: urges.count,
            resisted: urges.filter { $0.outcome == .resisted }.count,
            gaveIn: urges.filter { $0.outcome == .gaveIn }.count,
            undecided: urges.filter { $0.outcome == .undecided }.count,
            byHour: byHour,
            byWeekday: byWeekday,
            topTargets: top(targets),
            topContexts: top(contexts),
            averageIntensity: urges.isEmpty ? 0 : Double(intensity) / Double(urges.count)
        )
    }

    /// Guard entries group by what was guarded; hand-logged ones by their text.
    static func topic(of urge: UrgeEntry) -> String {
        if urge.source.isGuard, let name = urge.targetName ?? urge.target { return name }
        let text = urge.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text.isEmpty ? "(blank)" : text
    }

    private static func top(_ counts: [String: Int], limit: Int = 6) -> [Count] {
        counts.map { Count(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
            .prefix(limit)
            .map { $0 }
    }
}
