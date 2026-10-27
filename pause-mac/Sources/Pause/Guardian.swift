import AppKit
import PauseCore

enum GuardDecision {
    /// "Never mind": you walked away. Counts as a resisted urge.
    case backedOff(reason: String, waited: Int)
    /// You gave a reason and unlocked it for a while.
    case proceed(minutes: Int, reason: String, waited: Int)
}

/// Decides when a guarded app or website gets a speed bump or block screen, and handles the outcome.
@MainActor
final class Guardian {
    private unowned let state: AppState
    private var grants = GrantBook()
    private var overlay: GuardOverlayController?
    private var overlayRule: GuardRule?
    /// Bumped whenever unlocks change, so the menu can show "unlocked · 4 min left".
    private(set) var grantsVersion = 0

    init(state: AppState) {
        self.state = state
    }

    func check(_ front: Frontmost?, now: Date) {
        guard let front, front.bundleID != Bundle.main.bundleIdentifier else { return }

        if let showing = overlayRule {
            // Already asking. If you switched back to the guarded app behind the screen, hide it again.
            if showing.kind == .app, showing.matches(bundleID: front.bundleID, host: nil) {
                front.app.hide()
            }
            return
        }

        guard let rule = state.settings.guards.first(where: {
            $0.isActive(at: now, calendar: state.calendar) && $0.matches(bundleID: front.bundleID, host: front.host)
        }) else { return }
        guard !grants.isGranted(rule.id, at: now) else { return }
        present(rule, front: front, now: now)
    }

    struct Unlock: Identifiable {
        let rule: GuardRule
        let expires: Date
        var id: UUID { rule.id }
    }

    var activeUnlocks: [Unlock] {
        grants.active(at: Date()).compactMap { grant in
            state.settings.guards.first(where: { $0.id == grant.ruleID }).map { Unlock(rule: $0, expires: grant.expires) }
        }
    }

    /// Ends an unlock early. The next time you're on it, the guard screen comes back.
    func relock(_ ruleID: UUID) {
        grants.revoke(ruleID)
        grantsVersion += 1
        state.objectWillChange.send()
    }

    /// Shows a guard screen without anything being opened (screenshot tests).
    func preview(_ rule: GuardRule?) {
        guard let rule, overlayRule == nil else { return }
        let me = NSRunningApplication.current
        let front = Frontmost(app: me, bundleID: "demo", name: "Safari", host: rule.kind == .website ? rule.value : nil)
        present(rule, front: front, now: Date())
    }

    private func present(_ rule: GuardRule, front: Frontmost, now: Date) {
        if rule.kind == .app, front.bundleID != "demo" { front.app.hide() }

        let opens = GuardPolicy.opensToday(of: rule, urges: state.urges, now: now, calendar: state.calendar)
        let requirements = GuardPolicy.requirements(for: rule, opensToday: opens, settings: state.settings)
        let controller = GuardOverlayController(rule: rule, requirements: requirements, opensToday: opens) { [weak self] decision in
            self?.finish(rule, front: front, decision: decision)
        }
        overlay = controller
        overlayRule = rule
        controller.show()
    }

    private func finish(_ rule: GuardRule, front: Frontmost, decision: GuardDecision) {
        overlay?.close()
        overlay = nil
        overlayRule = nil
        let now = Date()

        let source: UrgeSource = rule.mode == .block ? .block : .speedBump
        switch decision {
        case let .backedOff(reason, _):
            let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            state.addUrge(UrgeEntry(
                date: now,
                text: text.isEmpty ? "Wanted to open \(rule.displayName)" : text,
                outcome: .resisted,
                context: front.description,
                source: source,
                target: rule.value,
                targetName: rule.displayName
            ))
            if rule.kind == .website {
                state.tracker.browser.closeCurrentTab(bundleID: front.bundleID)
                front.app.activate(options: [.activateIgnoringOtherApps])
            }

        case let .proceed(minutes, reason, _):
            state.addUrge(UrgeEntry(
                date: now,
                text: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                outcome: .gaveIn,
                context: front.description,
                source: source,
                target: rule.value,
                targetName: rule.displayName,
                unlockedMinutes: minutes
            ))
            grants.grant(rule.id, minutes: minutes, now: now)
            grantsVersion += 1
            if rule.kind == .app { front.app.unhide() }
            front.app.activate(options: [.activateIgnoringOtherApps])
        }
    }
}
