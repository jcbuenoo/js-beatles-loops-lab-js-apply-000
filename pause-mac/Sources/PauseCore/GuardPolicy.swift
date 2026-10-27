import Foundation

/// What a guard screen asks of you before it lets you through.
public struct GuardRequirements: Equatable {
    public var waitSeconds: Int
    public var minReasonLength: Int
    public var minReasonWords: Int
    public var unlockMinutes: [Int]
}

public enum GuardPolicy {
    public static func requirements(for rule: GuardRule, opensToday: Int, settings: PauseSettings) -> GuardRequirements {
        switch rule.mode {
        case .speedBump:
            let wait = settings.bumpBaseDelaySeconds + settings.bumpDelayStepSeconds * max(0, opensToday)
            return GuardRequirements(
                waitSeconds: min(max(settings.bumpBaseDelaySeconds, settings.bumpMaxDelaySeconds), max(0, wait)),
                minReasonLength: settings.bumpMinReasonLength,
                minReasonWords: 2,
                unlockMinutes: [5, 15, 30]
            )
        case .block:
            return GuardRequirements(
                waitSeconds: max(0, settings.blockDelaySeconds),
                minReasonLength: settings.blockMinReasonLength,
                minReasonWords: 6,
                unlockMinutes: [5, 10]
            )
        }
    }

    /// Rejects keyboard mashing: needs enough letters and enough *different* real words.
    public static func isReasonAcceptable(_ reason: String, _ req: GuardRequirements) -> Bool {
        reasonProblem(reason, req) == nil
    }

    /// A short explanation of what's missing, or nil when the reason is good enough.
    public static func reasonProblem(_ reason: String, _ req: GuardRequirements) -> String? {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < req.minReasonLength {
            return "\(trimmed.count)/\(req.minReasonLength) characters"
        }
        let words = trimmed.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 2 && Set($0).count > 1 }
        let distinct = Set(words)
        if distinct.count < req.minReasonWords {
            return "Use at least \(req.minReasonWords) different real words"
        }
        return nil
    }

    /// How many times today you went through (or tried to go through) this guard.
    public static func opensToday(of rule: GuardRule, urges: [UrgeEntry], now: Date, calendar: Calendar = .current) -> Int {
        urges.filter { $0.source.isGuard && $0.target == rule.value && calendar.isDate($0.date, inSameDayAs: now) }.count
    }
}

/// Temporary unlocks granted by a guard screen.
public struct GrantBook {
    private var expiries: [UUID: Date] = [:]

    public init() {}

    public mutating func grant(_ ruleID: UUID, minutes: Int, now: Date) {
        expiries[ruleID] = now.addingTimeInterval(TimeInterval(minutes * 60))
    }

    public func isGranted(_ ruleID: UUID, at now: Date) -> Bool {
        guard let expiry = expiries[ruleID] else { return false }
        return expiry > now
    }

    public mutating func revoke(_ ruleID: UUID) {
        expiries[ruleID] = nil
    }

    /// Unlocks still running, soonest-expiring first.
    public func active(at now: Date) -> [(ruleID: UUID, expires: Date)] {
        expiries.filter { $0.value > now }
            .map { (ruleID: $0.key, expires: $0.value) }
            .sorted { $0.expires < $1.expires }
    }
}
