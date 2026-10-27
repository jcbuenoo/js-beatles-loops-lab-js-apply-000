import Foundation

/// JSON files in ~/Library/Application Support/Pause. Nothing leaves your Mac.
///
///     settings.json
///     urges.json
///     activity/2026-10-27.json
public final class Store {
    public let root: URL
    private let calendar: Calendar
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL, calendar: Calendar = .current) {
        self.root = root
        self.calendar = calendar
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: activityDirectory, withIntermediateDirectories: true)
    }

    public static var defaultRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Pause", isDirectory: true)
    }

    public var activityDirectory: URL { root.appendingPathComponent("activity", isDirectory: true) }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: Settings

    public func loadSettings() -> PauseSettings {
        read(PauseSettings.self, from: root.appendingPathComponent("settings.json")) ?? PauseSettings()
    }

    public func saveSettings(_ settings: PauseSettings) {
        write(settings, to: root.appendingPathComponent("settings.json"))
    }

    // MARK: Urges

    public func loadUrges() -> [UrgeEntry] {
        read([UrgeEntry].self, from: root.appendingPathComponent("urges.json")) ?? []
    }

    public func saveUrges(_ urges: [UrgeEntry]) {
        write(urges, to: root.appendingPathComponent("urges.json"))
    }

    // MARK: Activity

    public func loadActivity(for day: Date) -> [ActivitySpan] {
        read([ActivitySpan].self, from: activityFile(for: day)) ?? []
    }

    /// Adds spans to the right day files, splitting any that cross midnight.
    public func appendActivity(_ spans: [ActivitySpan]) {
        guard !spans.isEmpty else { return }
        let pieces = spans.flatMap { $0.split(by: .day, calendar: calendar) }
        let byDay = Dictionary(grouping: pieces) { Store.dayKey($0.start, calendar: calendar) }
        for (_, daySpans) in byDay {
            guard let first = daySpans.first else { continue }
            let file = activityFile(for: first.start)
            var existing = read([ActivitySpan].self, from: file) ?? []
            existing.append(contentsOf: daySpans)
            write(existing, to: file)
        }
    }

    private func activityFile(for day: Date) -> URL {
        activityDirectory.appendingPathComponent("\(Store.dayKey(day, calendar: calendar)).json")
    }

    // MARK: Plumbing

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            // Keep the unreadable file instead of silently overwriting it on the next save.
            let backup = url.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: url, to: backup)
            return nil
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            NSLog("Pause: could not save \(url.lastPathComponent): \(error)")
        }
    }
}
