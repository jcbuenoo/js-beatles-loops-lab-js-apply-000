import AppKit
import PauseCore

/// Screenshot mode for automated tests: `Pause --demo <scene>` fills a throwaway data folder with
/// sample data and opens one screen. It only runs when PAUSE_DATA_DIR points somewhere other than
/// your real data, so it can never touch your own log.
@MainActor
enum Demo {
    static let scenes = ["menu", "today", "urges", "settings", "guard", "block", "urge-logger"]

    static var scene: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--demo"), i + 1 < args.count else { return nil }
        guard ProcessInfo.processInfo.environment["PAUSE_DATA_DIR"] != nil else {
            NSLog("Pause: --demo needs PAUSE_DATA_DIR so it doesn't touch your real data. Ignoring.")
            return nil
        }
        return args[i + 1]
    }

    static func run(_ scene: String, state: AppState, statusMenu: StatusMenuController?) {
        seedIfEmpty(state)
        // Give the menu bar a moment to settle before opening anything.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            switch scene {
            case "menu": statusMenu?.open()
            case "today": WindowManager.shared.show(.today)
            case "urges": WindowManager.shared.show(.urges)
            case "settings": WindowManager.shared.show(.settings)
            case "guard": state.guardian.preview(state.settings.guards.first { $0.mode == .speedBump })
            case "block": state.guardian.preview(state.settings.guards.first { $0.mode == .block })
            case "urge-logger": state.urgeLogger.show()
            default: NSLog("Pause: unknown demo scene \(scene). Try: \(scenes.joined(separator: ", "))")
            }
        }
    }

    private static func seedIfEmpty(_ state: AppState) {
        guard state.urges.isEmpty else { return }
        let now = Date()

        var settings = state.settings
        settings.dailySummaryEnabled = false
        settings.guards = [
            GuardRule(kind: .website, value: "reddit.com", displayName: "reddit.com", mode: .speedBump),
            GuardRule(kind: .website, value: "youtube.com", displayName: "youtube.com", mode: .block,
                      schedule: GuardSchedule(weekdays: Set(2...6), startMinute: 9 * 60, endMinute: 17 * 60)),
            GuardRule(kind: .app, value: "com.apple.Music", displayName: "Music", mode: .speedBump),
        ]
        state.settings = settings

        // Six hours of a plausible day, ending now.
        let pattern: [(String, String, String?, Int)] = [
            ("Xcode", "com.apple.dt.Xcode", nil, 34),
            ("Safari", "com.apple.Safari", "youtube.com", 12),
            ("Slack", "com.tinyspeck.slackmacgap", nil, 6),
            ("Safari", "com.apple.Safari", "docs.google.com", 22),
            ("Safari", "com.apple.Safari", "reddit.com", 9),
            ("Notes", "com.apple.Notes", nil, 5),
            ("Xcode", "com.apple.dt.Xcode", nil, 48),
            ("Messages", "com.apple.MobileSMS", nil, 4),
        ]
        var spans: [ActivitySpan] = []
        var cursor = now.addingTimeInterval(-6 * 3600)
        var i = 0
        while cursor < now {
            let (name, bundleID, domain, minutes) = pattern[i % pattern.count]
            let end = min(now, cursor.addingTimeInterval(TimeInterval(minutes * 60)))
            spans.append(ActivitySpan(start: cursor, end: end, appName: name, bundleID: bundleID, domain: domain))
            cursor = end.addingTimeInterval(20)
            i += 1
        }
        state.store.appendActivity(spans)
        state.activitySaved()

        let samples: [(Int, String, Int, UrgeOutcome, UrgeSource, String?)] = [
            (300, "check reddit", 4, .resisted, .manual, nil),
            (250, "Wanted to open reddit.com", 3, .resisted, .speedBump, "reddit.com"),
            (190, "look up the API docs for the date picker", 3, .gaveIn, .speedBump, "reddit.com"),
            (140, "buy headphones", 5, .resisted, .manual, nil),
            (90, "snack", 2, .gaveIn, .manual, nil),
            (40, "Wanted to open youtube.com", 4, .resisted, .block, "youtube.com"),
            (10, "switch to a different task", 3, .undecided, .manual, nil),
        ]
        for (minutesAgo, text, intensity, outcome, source, target) in samples {
            state.addUrge(UrgeEntry(
                date: now.addingTimeInterval(TimeInterval(-minutesAgo * 60)),
                text: text,
                intensity: intensity,
                outcome: outcome,
                context: "Xcode",
                source: source,
                target: target,
                targetName: target,
                unlockedMinutes: outcome == .gaveIn && source.isGuard ? 15 : nil
            ))
        }
    }
}
