import AppKit
import IOKit.pwr_mgt
import PauseCore

/// What's in front of you right now.
struct Frontmost {
    let app: NSRunningApplication
    let bundleID: String
    let name: String
    /// Website host, when the app is a supported browser and it answered.
    let host: String?

    var description: String {
        if let host { return "\(name) — \(host)" }
        return name
    }
}

/// Watches the frontmost app (and browser tab) every couple of seconds, records time spans,
/// and hands each look to the guardian so speed bumps and blocks can kick in.
@MainActor
final class ActivityTracker: NSObject {
    private unowned let state: AppState
    let browser = BrowserBridge()
    private var recorder = ActivityRecorder(maxGap: 30)
    private var tickTimer: Timer?
    private var saveTimer: Timer?
    private var tickCount = 0
    private var away = false
    private(set) var lastFrontmost: Frontmost?

    init(state: AppState) {
        self.state = state
        super.init()
    }

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(appActivated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        ws.addObserver(self, selector: #selector(wentAway(_:)), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(wentAway(_:)), name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(wentAway(_:)), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        ws.addObserver(self, selector: #selector(cameBack(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(cameBack(_:)), name: NSWorkspace.screensDidWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(cameBack(_:)), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(wentAway(_:)), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(cameBack(_:)), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)

        tickTimer = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        tickTimer?.tolerance = 0.5
        saveTimer = Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(flush), userInfo: nil, repeats: true)
        tick()
    }

    /// Saves everything recorded so far.
    @objc func flush() {
        state.store.appendActivity(recorder.drain(includeOpen: true))
        state.activitySaved()
    }

    func unsavedSpans() -> [ActivitySpan] {
        recorder.pending()
    }

    @objc private func appActivated(_ note: Notification) {
        // React right away so a guarded app is covered before you can start using it.
        tick()
    }

    @objc private func wentAway(_ note: Notification) {
        away = true
        recorder.observe(nil, at: Date())
    }

    @objc private func cameBack(_ note: Notification) {
        away = false
        tick()
    }

    @objc private func tick() {
        let now = Date()
        tickCount &+= 1
        let front = away ? nil : readFrontmost()
        lastFrontmost = front ?? lastFrontmost

        var sample: ActivitySample?
        if let front, !isIdle() {
            sample = ActivitySample(
                appName: front.name,
                bundleID: front.bundleID,
                domain: state.settings.trackBrowserDomains ? front.host : nil
            )
        }
        recorder.observe(sample, at: now)
        state.guardian.check(front, now: now)
        state.didTick(now, tickCount: tickCount)
    }

    private func readFrontmost() -> Frontmost? {
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier else { return nil }
        var host: String?
        let needsURL = state.settings.trackBrowserDomains || state.settings.guards.contains { $0.kind == .website }
        if needsURL, BrowserBridge.isSupported(bundleID) {
            host = browser.currentURL(bundleID: bundleID).flatMap(DomainMatcher.host(from:))
        }
        return Frontmost(app: app, bundleID: bundleID, name: app.localizedName ?? bundleID, host: host)
    }

    /// No input for a while counts as away, unless something is holding the display awake
    /// (a playing video), because watching YouTube without touching anything is exactly the time
    /// this report should catch.
    private func isIdle() -> Bool {
        let inputs: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .leftMouseDragged]
        let seconds = inputs.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
        guard seconds >= Double(state.settings.idleThresholdSeconds) else { return false }
        return !Self.displayIsHeldAwake()
    }

    private static func displayIsHeldAwake() -> Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let dict = status?.takeRetainedValue() as? [String: Any]
        else { return false }
        let count = (dict["PreventUserIdleDisplaySleep"] as? NSNumber)?.intValue ?? 0
        return count > 0
    }
}
