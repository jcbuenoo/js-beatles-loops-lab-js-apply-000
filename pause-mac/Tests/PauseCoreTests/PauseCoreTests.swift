import XCTest
@testable import PauseCore

final class DomainMatcherTests: XCTestCase {
    func testHostFromURL() {
        XCTAssertEqual(DomainMatcher.host(from: "https://www.Reddit.com/r/adhd"), "reddit.com")
        XCTAssertEqual(DomainMatcher.host(from: "http://m.youtube.com/watch?v=1"), "m.youtube.com")
        XCTAssertNil(DomainMatcher.host(from: "about:blank"))
        XCTAssertNil(DomainMatcher.host(from: ""))
    }

    func testNormalize() {
        XCTAssertEqual(DomainMatcher.normalize(" https://www.YouTube.com/feed "), "youtube.com")
        XCTAssertEqual(DomainMatcher.normalize("reddit.com:443/r"), "reddit.com")
    }

    func testMatchesSubdomainsOnly() {
        XCTAssertTrue(DomainMatcher.matches(host: "m.youtube.com", rule: "youtube.com"))
        XCTAssertTrue(DomainMatcher.matches(host: "youtube.com", rule: "www.youtube.com"))
        XCTAssertFalse(DomainMatcher.matches(host: "notyoutube.com", rule: "youtube.com"))
    }
}

final class GuardTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testSpeedBumpWaitGrowsAndCaps() {
        let rule = GuardRule(kind: .website, value: "reddit.com", displayName: "Reddit")
        let s = PauseSettings()
        XCTAssertEqual(GuardPolicy.requirements(for: rule, opensToday: 0, settings: s).waitSeconds, 10)
        XCTAssertEqual(GuardPolicy.requirements(for: rule, opensToday: 2, settings: s).waitSeconds, 20)
        XCTAssertEqual(GuardPolicy.requirements(for: rule, opensToday: 50, settings: s).waitSeconds, 60)
    }

    func testBlockIsStricter() {
        let rule = GuardRule(kind: .app, value: "com.hnc.Discord", displayName: "Discord", mode: .block)
        let req = GuardPolicy.requirements(for: rule, opensToday: 0, settings: PauseSettings())
        XCTAssertEqual(req.waitSeconds, 60)
        XCTAssertEqual(req.minReasonLength, 40)
        XCTAssertEqual(req.unlockMinutes, [5, 10])
    }

    func testReasonRejectsMashing() {
        let req = GuardRequirements(waitSeconds: 0, minReasonLength: 10, minReasonWords: 2, unlockMinutes: [5])
        XCTAssertFalse(GuardPolicy.isReasonAcceptable("short", req))
        XCTAssertFalse(GuardPolicy.isReasonAcceptable("aaaaaaaaaaaaaaaa", req))
        XCTAssertFalse(GuardPolicy.isReasonAcceptable("asdf asdf asdf asdf", req))
        XCTAssertTrue(GuardPolicy.isReasonAcceptable("reply to my landlord", req))
    }

    func testScheduleDaytimeAndOvernight() {
        // 2026-10-27 is a Tuesday (weekday 3).
        let work = GuardSchedule(weekdays: Set(2...6), startMinute: 9 * 60, endMinute: 17 * 60)
        XCTAssertTrue(work.isActive(at: date(2026, 10, 27, 10), calendar: calendar))
        XCTAssertFalse(work.isActive(at: date(2026, 10, 27, 17), calendar: calendar))
        XCTAssertFalse(work.isActive(at: date(2026, 10, 25, 10), calendar: calendar)) // Sunday

        let night = GuardSchedule(weekdays: [3], startMinute: 22 * 60, endMinute: 6 * 60)
        XCTAssertTrue(night.isActive(at: date(2026, 10, 27, 23), calendar: calendar))
        XCTAssertTrue(night.isActive(at: date(2026, 10, 28, 2), calendar: calendar)) // Wed early = Tue night
        XCTAssertFalse(night.isActive(at: date(2026, 10, 29, 2), calendar: calendar))
    }

    func testGrantsExpire() {
        var book = GrantBook()
        let id = UUID()
        let now = date(2026, 10, 27, 12)
        book.grant(id, minutes: 5, now: now)
        XCTAssertTrue(book.isGranted(id, at: now.addingTimeInterval(299)))
        XCTAssertFalse(book.isGranted(id, at: now.addingTimeInterval(301)))
    }

    func testOpensTodayCountsOnlyThisGuardToday() {
        let rule = GuardRule(kind: .website, value: "reddit.com", displayName: "Reddit")
        let now = date(2026, 10, 27, 15)
        let urges = [
            UrgeEntry(date: date(2026, 10, 27, 9), text: "x", outcome: .gaveIn, source: .speedBump, target: "reddit.com"),
            UrgeEntry(date: date(2026, 10, 27, 11), text: "x", outcome: .resisted, source: .speedBump, target: "reddit.com"),
            UrgeEntry(date: date(2026, 10, 26, 11), text: "x", outcome: .resisted, source: .speedBump, target: "reddit.com"),
            UrgeEntry(date: date(2026, 10, 27, 11), text: "x", outcome: .resisted, source: .speedBump, target: "x.com"),
            UrgeEntry(date: date(2026, 10, 27, 12), text: "reddit", outcome: .resisted, source: .manual),
        ]
        XCTAssertEqual(GuardPolicy.opensToday(of: rule, urges: urges, now: now, calendar: calendar), 2)
    }
}

final class RecorderAndReportTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    let safari = ActivitySample(appName: "Safari", bundleID: "com.apple.Safari", domain: "youtube.com")
    let xcode = ActivitySample(appName: "Xcode", bundleID: "com.apple.dt.Xcode")

    func testRecorderSplitsOnSwitchAndIdle() {
        var r = ActivityRecorder(maxGap: 30)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        r.observe(xcode, at: t0)
        r.observe(xcode, at: t0 + 10)
        r.observe(safari, at: t0 + 20)   // switch: Xcode gets 0–20
        r.observe(safari, at: t0 + 30)
        r.observe(nil, at: t0 + 32)      // idle: Safari gets 20–32
        r.observe(xcode, at: t0 + 100)
        r.observe(xcode, at: t0 + 200)   // gap > 30s: new span, the missing time isn't claimed
        let spans = r.drain(includeOpen: true)
        XCTAssertEqual(spans.map(\.duration), [20, 12])
        XCTAssertEqual(r.current?.start, t0 + 200)
    }

    func testDrainKeepsOpenSpanGoing() {
        var r = ActivityRecorder()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        r.observe(xcode, at: t0)
        r.observe(xcode, at: t0 + 10)
        XCTAssertEqual(r.drain(includeOpen: true).map(\.duration), [10])
        r.observe(xcode, at: t0 + 15)
        XCTAssertEqual(r.drain(includeOpen: true).map(\.duration), [5])
    }

    func testSplitAcrossMidnight() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 23, minute: 50))!
        let span = ActivitySpan(start: start, end: start + 20 * 60, sample: xcode)
        let parts = span.split(by: .day, calendar: calendar)
        XCTAssertEqual(parts.map(\.duration), [600, 600])
    }

    func testDayReport() {
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 9))!
        let spans = [
            ActivitySpan(start: day, end: day + 3600, sample: xcode),
            ActivitySpan(start: day + 3600, end: day + 3600 + 1800, sample: safari),
            ActivitySpan(start: day + 5400, end: day + 5400 + 600, sample: xcode),
        ]
        let urges = [
            UrgeEntry(date: day + 100, text: "check youtube", outcome: .resisted),
            UrgeEntry(date: day + 200, text: "snack", outcome: .gaveIn),
        ]
        let settings = PauseSettings()
        let report = DayReport.build(day: day, spans: spans, urges: urges, categorize: settings.category(for:), calendar: calendar)
        XCTAssertEqual(report.totalActive, 6000)
        XCTAssertEqual(report.seconds(in: .distracting), 1800)
        XCTAssertEqual(report.rows.first?.name, "Xcode")
        XCTAssertEqual(report.rows.first?.seconds, 4200)
        XCTAssertEqual(report.contextSwitches, 2)
        XCTAssertEqual(report.longestFocus, 3600)
        XCTAssertEqual(report.urgesResisted, 1)
        XCTAssertTrue(report.headline.contains("mostly youtube.com"), report.headline)
    }

    func testOverridesBeatDefaultsIncludingParentDomains() {
        var s = PauseSettings()
        XCTAssertEqual(s.category(for: "domain:m.youtube.com"), .distracting)
        s.categoryOverrides["domain:youtube.com"] = .intentional
        XCTAssertEqual(s.category(for: "domain:m.youtube.com"), .intentional)
    }

    func testSettingsDecodeOldFiles() throws {
        let json = #"{"bumpBaseDelaySeconds": 20}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(PauseSettings.self, from: json)
        XCTAssertEqual(s.bumpBaseDelaySeconds, 20)
        XCTAssertEqual(s.blockDelaySeconds, 60)
    }

    func testStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(root: dir, calendar: calendar)
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 23, minute: 50))!
        store.appendActivity([ActivitySpan(start: start, end: start + 20 * 60, sample: xcode)])
        XCTAssertEqual(store.loadActivity(for: start).count, 1)
        XCTAssertEqual(store.loadActivity(for: start + 3600).count, 1)
        store.saveUrges([UrgeEntry(text: "x", outcome: .undecided)])
        XCTAssertEqual(store.loadUrges().count, 1)
    }

    func testInsights() {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 22))!
        let urges = [
            UrgeEntry(date: base, text: "Check Reddit", intensity: 4, outcome: .resisted),
            UrgeEntry(date: base + 60, text: "check reddit ", intensity: 2, outcome: .gaveIn),
            UrgeEntry(date: base + 120, text: "x", outcome: .resisted, source: .block, target: "x.com", targetName: "X"),
        ]
        let i = UrgeInsights.build(urges, calendar: calendar)
        XCTAssertEqual(i.total, 3)
        XCTAssertEqual(i.peakHour, 22)
        XCTAssertEqual(i.topTargets.first?.name, "check reddit")
        XCTAssertEqual(i.topTargets.first?.count, 2)
        XCTAssertEqual(i.resistRate, 2.0 / 3.0, accuracy: 0.001)
    }
}
