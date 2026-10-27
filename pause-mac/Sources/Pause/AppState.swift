import AppKit
import Combine
import PauseCore
import ServiceManagement

/// The one shared brain: settings, the urge log, the activity tracker and the guard screens.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let store: Store
    let calendar = Calendar.current

    @Published var settings: PauseSettings {
        didSet {
            if settings != oldValue { store.saveSettings(settings) }
        }
    }
    @Published private(set) var urges: [UrgeEntry]
    /// Bumped every few seconds so open windows refresh their "today" numbers.
    @Published private(set) var refreshToken = 0

    private(set) lazy var tracker = ActivityTracker(state: self)
    private(set) lazy var guardian = Guardian(state: self)
    private(set) lazy var urgeLogger = UrgeLoggerController(state: self)
    private var hotKey: HotKey?
    private var started = false

    private var todayCache: (key: String, spans: [ActivitySpan])?

    private init() {
        // PAUSE_DATA_DIR lets the automated tests use a throwaway folder instead of your real data.
        let root = ProcessInfo.processInfo.environment["PAUSE_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        let store = Store(root: root ?? Store.defaultRoot)
        self.store = store
        settings = store.loadSettings()
        urges = store.loadUrges()
    }

    func start() {
        guard !started else { return }
        started = true
        tracker.start()
        // ⌥⌘U from anywhere opens the urge logger.
        hotKey = HotKey(keyCode: HotKey.keyU, modifiers: HotKey.optionCommand) { [weak self] in
            self?.urgeLogger.show()
        }
        if Demo.scene == nil { Notifier.shared.setUp() }
    }

    func stop() {
        tracker.flush()
    }

    // MARK: Urges

    func addUrge(_ entry: UrgeEntry) {
        urges.append(entry)
        store.saveUrges(urges)
    }

    func setOutcome(_ outcome: UrgeOutcome, for id: UUID) {
        guard let i = urges.firstIndex(where: { $0.id == id }) else { return }
        urges[i].outcome = outcome
        store.saveUrges(urges)
    }

    func deleteUrge(_ id: UUID) {
        urges.removeAll { $0.id == id }
        store.saveUrges(urges)
    }

    // MARK: Reports

    func report(for day: Date) -> DayReport {
        var spans: [ActivitySpan]
        if calendar.isDateInToday(day) {
            // Today's file is re-read only after the tracker saves to it, not on every redraw.
            let key = Store.dayKey(day, calendar: calendar)
            if let cache = todayCache, cache.key == key {
                spans = cache.spans
            } else {
                spans = store.loadActivity(for: day)
                todayCache = (key: key, spans: spans)
            }
            spans += tracker.unsavedSpans()
        } else {
            spans = store.loadActivity(for: day)
        }
        return DayReport.build(day: day, spans: spans, urges: urges, categorize: settings.category(for:), calendar: calendar)
    }

    func activitySaved() {
        todayCache = nil
    }

    func setCategory(_ category: AppCategory, for key: String) {
        settings.categoryOverrides[key] = category
    }

    /// Called by the tracker on every tick.
    func didTick(_ now: Date, tickCount: Int) {
        if tickCount % 5 == 0 { refreshToken &+= 1 }
        checkDailySummary(now)
    }

    private func checkDailySummary(_ now: Date) {
        guard settings.dailySummaryEnabled else { return }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let today = Store.dayKey(now, calendar: calendar)
        guard minute >= settings.dailySummaryMinute, settings.lastSummaryDayKey != today else { return }
        settings.lastSummaryDayKey = today
        let report = report(for: now)
        // Skip days you barely used the Mac.
        guard report.totalActive >= 10 * 60 else { return }
        Notifier.shared.post(title: "Where did your day go?", body: report.headline, identifier: "daily-\(today)")
    }

    // MARK: Login item

    var launchesAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchesAtLogin(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            objectWillChange.send()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
