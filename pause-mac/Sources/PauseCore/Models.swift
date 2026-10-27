import Foundation

// MARK: - Categories

public enum AppCategory: String, Codable, CaseIterable, Identifiable {
    case intentional
    case neutral
    case distracting

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .intentional: return "Intentional"
        case .neutral: return "Neutral"
        case .distracting: return "Distracting"
        }
    }
}

// MARK: - Activity

/// What was in front of you at one moment.
public struct ActivitySample: Equatable {
    public var appName: String
    public var bundleID: String
    /// Website host when the frontmost app is a supported browser.
    public var domain: String?

    public init(appName: String, bundleID: String, domain: String? = nil) {
        self.appName = appName
        self.bundleID = bundleID
        self.domain = domain
    }

    public var key: String { ActivitySpan.key(bundleID: bundleID, domain: domain) }
}

/// A continuous stretch of time spent in one app (or one website).
public struct ActivitySpan: Codable, Equatable {
    public var start: Date
    public var end: Date
    public var appName: String
    public var bundleID: String
    public var domain: String?

    public init(start: Date, end: Date, appName: String, bundleID: String, domain: String? = nil) {
        self.start = start
        self.end = end
        self.appName = appName
        self.bundleID = bundleID
        self.domain = domain
    }

    public init(start: Date, end: Date, sample: ActivitySample) {
        self.init(start: start, end: end, appName: sample.appName, bundleID: sample.bundleID, domain: sample.domain)
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    public var key: String { ActivitySpan.key(bundleID: bundleID, domain: domain) }
    public var displayName: String { domain ?? appName }

    public static func key(bundleID: String, domain: String?) -> String {
        if let domain { return "domain:\(domain)" }
        return bundleID
    }

    /// Splits the span at every boundary of `component` (e.g. `.day`, `.hour`).
    public func split(by component: Calendar.Component, calendar: Calendar) -> [ActivitySpan] {
        guard end > start else { return [self] }
        var parts: [ActivitySpan] = []
        var cursor = start
        while cursor < end {
            guard let interval = calendar.dateInterval(of: component, for: cursor), interval.end > cursor else { break }
            var part = self
            part.start = cursor
            part.end = min(end, interval.end)
            parts.append(part)
            cursor = part.end
        }
        if cursor < end {
            var rest = self
            rest.start = cursor
            parts.append(rest)
        }
        return parts
    }

    /// Joins spans of the same app/site that follow each other within `maxGap` seconds.
    /// The tracker saves time in one-minute pieces; this turns them back into one span per sitting.
    public static func merged(_ spans: [ActivitySpan], maxGap: TimeInterval = 5) -> [ActivitySpan] {
        var result: [ActivitySpan] = []
        result.reserveCapacity(spans.count)
        for span in spans.sorted(by: { $0.start < $1.start }) {
            if var last = result.last, last.key == span.key, span.start.timeIntervalSince(last.end) <= maxGap {
                last.end = max(last.end, span.end)
                result[result.count - 1] = last
            } else {
                result.append(span)
            }
        }
        return result
    }

    /// The part of the span inside `interval`, or nil if they don't overlap.
    public func clipped(to interval: DateInterval) -> ActivitySpan? {
        let s = max(start, interval.start)
        let e = min(end, interval.end)
        guard e > s else { return nil }
        var part = self
        part.start = s
        part.end = e
        return part
    }
}

// MARK: - Urges

public enum UrgeOutcome: String, Codable, CaseIterable, Identifiable {
    case resisted
    case gaveIn
    case undecided

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .resisted: return "Resisted"
        case .gaveIn: return "Gave in"
        case .undecided: return "Still deciding"
        }
    }
}

public enum UrgeSource: String, Codable {
    /// Logged by hand with the hotkey.
    case manual
    /// Created by a speed bump screen.
    case speedBump
    /// Created by a block screen.
    case block

    public var isGuard: Bool { self != .manual }
}

public struct UrgeEntry: Codable, Identifiable, Equatable {
    public var id: UUID
    public var date: Date
    public var text: String
    /// 1 (barely) to 5 (overwhelming).
    public var intensity: Int
    public var outcome: UrgeOutcome
    /// What you were doing at the time, e.g. "Safari — youtube.com".
    public var context: String?
    public var source: UrgeSource
    /// For guard-created entries: the guarded bundle ID or domain.
    public var target: String?
    /// For guard-created entries: the name shown on the guard screen.
    public var targetName: String?
    /// For guard-created entries where you went ahead: how long you unlocked it for.
    public var unlockedMinutes: Int?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        text: String,
        intensity: Int = 3,
        outcome: UrgeOutcome,
        context: String? = nil,
        source: UrgeSource = .manual,
        target: String? = nil,
        targetName: String? = nil,
        unlockedMinutes: Int? = nil
    ) {
        self.id = id
        self.date = date
        self.text = text
        self.intensity = min(5, max(1, intensity))
        self.outcome = outcome
        self.context = context
        self.source = source
        self.target = target
        self.targetName = targetName
        self.unlockedMinutes = unlockedMinutes
    }
}

// MARK: - Guards (speed bumps and blocks)

public enum GuardMode: String, Codable, CaseIterable, Identifiable {
    /// Pause, breathe, say why, then you may open it. The wait grows with each open that day.
    case speedBump
    /// Blocked. Unlocking takes a long wait, a detailed reason, and only lasts a few minutes.
    case block

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .speedBump: return "Speed bump"
        case .block: return "Block"
        }
    }
}

/// When a guard is active. Minutes are counted from midnight; an end before the start wraps past midnight.
public struct GuardSchedule: Codable, Hashable {
    /// Calendar weekday numbers: 1 = Sunday … 7 = Saturday.
    public var weekdays: Set<Int>
    public var startMinute: Int
    public var endMinute: Int

    public init(weekdays: Set<Int> = Set(1...7), startMinute: Int = 9 * 60, endMinute: Int = 17 * 60) {
        self.weekdays = weekdays
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    public func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday else { return false }
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if startMinute == endMinute { return weekdays.contains(weekday) }
        if startMinute < endMinute {
            return weekdays.contains(weekday) && minute >= startMinute && minute < endMinute
        }
        // Overnight, e.g. 22:00–06:00: the early-morning part belongs to the previous day's schedule.
        let yesterday = weekday == 1 ? 7 : weekday - 1
        return (minute >= startMinute && weekdays.contains(weekday)) || (minute < endMinute && weekdays.contains(yesterday))
    }

    public var summary: String {
        let days: String
        if weekdays.count == 7 {
            days = "every day"
        } else if weekdays == Set(2...6) {
            days = "weekdays"
        } else if weekdays == [1, 7] {
            days = "weekends"
        } else {
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            days = weekdays.sorted().map { names[$0 - 1] }.joined(separator: ", ")
        }
        return "\(GuardSchedule.clock(startMinute))–\(GuardSchedule.clock(endMinute)), \(days)"
    }

    public static func clock(_ minute: Int) -> String {
        let h = (minute / 60) % 24
        let m = minute % 60
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d", hour12, m) + (h < 12 ? " AM" : " PM")
    }
}

public struct GuardRule: Codable, Identifiable, Hashable {
    public enum Kind: String, Codable {
        case app
        case website
    }

    public var id: UUID
    public var kind: Kind
    /// Bundle ID for apps, domain (e.g. "reddit.com") for websites.
    public var value: String
    public var displayName: String
    public var mode: GuardMode
    /// nil means the guard is always on.
    public var schedule: GuardSchedule?

    public init(id: UUID = UUID(), kind: Kind, value: String, displayName: String, mode: GuardMode = .speedBump, schedule: GuardSchedule? = nil) {
        self.id = id
        self.kind = kind
        self.value = kind == .website ? DomainMatcher.normalize(value) : value
        self.displayName = displayName
        self.mode = mode
        self.schedule = schedule
    }

    public func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        schedule?.isActive(at: date, calendar: calendar) ?? true
    }

    public func matches(bundleID: String, host: String?) -> Bool {
        switch kind {
        case .app:
            return bundleID == value
        case .website:
            guard let host else { return false }
            return DomainMatcher.matches(host: host, rule: value)
        }
    }
}
