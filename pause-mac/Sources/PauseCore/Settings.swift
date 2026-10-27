import Foundation

public struct PauseSettings: Codable, Equatable {
    public var guards: [GuardRule] = []

    // Speed bump: wait = base + step × (times opened today), capped.
    public var bumpBaseDelaySeconds = 10
    public var bumpDelayStepSeconds = 5
    public var bumpMaxDelaySeconds = 60
    public var bumpMinReasonLength = 10

    // Block: a long wait, a real reason, and short unlocks.
    public var blockDelaySeconds = 60
    public var blockMinReasonLength = 40

    /// Your own labels, keyed like `ActivitySpan.key` ("com.apple.Safari" or "domain:youtube.com").
    public var categoryOverrides: [String: AppCategory] = [:]

    public var trackBrowserDomains = true
    /// No keyboard/mouse input for this long (and no video playing) counts as away.
    public var idleThresholdSeconds = 180

    public var dailySummaryEnabled = true
    /// Minutes after midnight.
    public var dailySummaryMinute = 21 * 60
    public var lastSummaryDayKey: String?

    public init() {}

    public func category(for key: String) -> AppCategory {
        if let c = categoryOverrides[key] { return c }
        if key.hasPrefix("domain:") {
            let host = String(key.dropFirst("domain:".count))
            for candidate in DomainMatcher.candidates(for: host) {
                if let c = categoryOverrides["domain:\(candidate)"] { return c }
            }
        }
        return DefaultCategories.guess(key)
    }

    // Decoding field by field means settings files from older versions keep working.
    private enum CodingKeys: String, CodingKey {
        case guards, bumpBaseDelaySeconds, bumpDelayStepSeconds, bumpMaxDelaySeconds, bumpMinReasonLength
        case blockDelaySeconds, blockMinReasonLength, categoryOverrides, trackBrowserDomains, idleThresholdSeconds
        case dailySummaryEnabled, dailySummaryMinute, lastSummaryDayKey
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PauseSettings()
        guards = try c.decodeIfPresent([GuardRule].self, forKey: .guards) ?? d.guards
        bumpBaseDelaySeconds = try c.decodeIfPresent(Int.self, forKey: .bumpBaseDelaySeconds) ?? d.bumpBaseDelaySeconds
        bumpDelayStepSeconds = try c.decodeIfPresent(Int.self, forKey: .bumpDelayStepSeconds) ?? d.bumpDelayStepSeconds
        bumpMaxDelaySeconds = try c.decodeIfPresent(Int.self, forKey: .bumpMaxDelaySeconds) ?? d.bumpMaxDelaySeconds
        bumpMinReasonLength = try c.decodeIfPresent(Int.self, forKey: .bumpMinReasonLength) ?? d.bumpMinReasonLength
        blockDelaySeconds = try c.decodeIfPresent(Int.self, forKey: .blockDelaySeconds) ?? d.blockDelaySeconds
        blockMinReasonLength = try c.decodeIfPresent(Int.self, forKey: .blockMinReasonLength) ?? d.blockMinReasonLength
        categoryOverrides = try c.decodeIfPresent([String: AppCategory].self, forKey: .categoryOverrides) ?? d.categoryOverrides
        trackBrowserDomains = try c.decodeIfPresent(Bool.self, forKey: .trackBrowserDomains) ?? d.trackBrowserDomains
        idleThresholdSeconds = try c.decodeIfPresent(Int.self, forKey: .idleThresholdSeconds) ?? d.idleThresholdSeconds
        dailySummaryEnabled = try c.decodeIfPresent(Bool.self, forKey: .dailySummaryEnabled) ?? d.dailySummaryEnabled
        dailySummaryMinute = try c.decodeIfPresent(Int.self, forKey: .dailySummaryMinute) ?? d.dailySummaryMinute
        lastSummaryDayKey = try c.decodeIfPresent(String.self, forKey: .lastSummaryDayKey)
    }
}

/// Starting guesses so the first report is useful before you've labelled anything.
public enum DefaultCategories {
    static let distractingDomains: Set<String> = [
        "youtube.com", "reddit.com", "x.com", "twitter.com", "instagram.com", "facebook.com",
        "tiktok.com", "netflix.com", "twitch.tv", "news.ycombinator.com", "hulu.com",
        "disneyplus.com", "max.com", "primevideo.com", "pinterest.com", "tumblr.com", "9gag.com",
        "threads.net", "bsky.app", "espn.com", "cnn.com", "foxnews.com",
    ]
    static let intentionalDomains: Set<String> = [
        "docs.google.com", "sheets.google.com", "slides.google.com", "github.com", "gitlab.com",
        "notion.so", "figma.com", "claude.ai", "stackoverflow.com", "developer.apple.com",
        "overleaf.com", "linear.app", "coursera.org", "khanacademy.org",
    ]
    static let distractingApps: Set<String> = [
        "com.hnc.Discord", "com.valvesoftware.steam", "com.apple.TV", "com.netflix.Netflix",
        "com.apple.gamecenter", "com.reddit.Reddit", "com.facebook.archon",
    ]
    static let intentionalApps: Set<String> = [
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
        "com.apple.iWork.Pages", "com.apple.iWork.Numbers", "com.apple.iWork.Keynote",
        "com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint",
        "notion.id", "md.obsidian", "com.figma.Desktop", "com.apple.Terminal",
        "com.googlecode.iterm2", "com.jetbrains.intellij", "com.sublimetext.4",
        "com.anthropic.claudefordesktop",
    ]

    public static func guess(_ key: String) -> AppCategory {
        if key.hasPrefix("domain:") {
            let host = String(key.dropFirst("domain:".count))
            for candidate in DomainMatcher.candidates(for: host) {
                if distractingDomains.contains(candidate) { return .distracting }
                if intentionalDomains.contains(candidate) { return .intentional }
            }
            return .neutral
        }
        if distractingApps.contains(key) { return .distracting }
        if intentionalApps.contains(key) { return .intentional }
        return .neutral
    }
}
