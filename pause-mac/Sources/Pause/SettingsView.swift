import AppKit
import PauseCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var newSite = ""
    @State private var newSiteMode: GuardMode = .speedBump
    @State private var pendingRemoval: GuardRule?
    @State private var loginError: String?

    var body: some View {
        let _ = state.refreshToken
        Form {
            guardsSection
            timingSection
            trackingSection
            summarySection
            categoriesSection
            generalSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 520)
        .alert(
            "Remove the guard on \(pendingRemoval?.displayName ?? "")?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { rule in
            Button("Keep it", role: .cancel) {}
            Button("Remove", role: .destructive) {
                state.settings.guards.removeAll { $0.id == rule.id }
            }
        } message: { _ in
            Text("You set this up for a reason. If this is a weak moment, close this window and come back tomorrow.")
        }
    }

    // MARK: Guards

    private var guardsSection: some View {
        Section {
            if state.settings.guards.isEmpty {
                Text("Nothing guarded yet. Add the apps and sites you open on autopilot.")
                    .foregroundStyle(.secondary)
            }
            ForEach($state.settings.guards) { $rule in
                GuardRow(rule: $rule) { pendingRemoval = rule }
            }

            HStack {
                Button {
                    addApp()
                } label: {
                    Label("Add app…", systemImage: "app.badge")
                }
                Spacer()
            }
            HStack {
                TextField("Add website", text: $newSite, prompt: Text("reddit.com"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addSite)
                Picker("Mode", selection: $newSiteMode) {
                    ForEach(GuardMode.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 130)
                Button("Add website", action: addSite)
                    .disabled(DomainMatcher.normalize(newSite).isEmpty)
            }

            if let error = state.tracker.browser.lastError {
                VStack(alignment: .leading, spacing: 6) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Button("Open Automation settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        } header: {
            Text("Guards")
        } footer: {
            Text("Speed bump: breathe, say why, then open it. The wait grows each time that day. Block: a long wait and a detailed reason, and it only unlocks for a few minutes. Website guards work in Safari, Chrome, Arc, Brave, Edge and Vivaldi. Firefox isn't supported.")
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Guard"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier,
                  !state.settings.guards.contains(where: { $0.kind == .app && $0.value == bundleID })
            else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            state.settings.guards.append(GuardRule(kind: .app, value: bundleID, displayName: name))
        }
    }

    private func addSite() {
        let domain = DomainMatcher.normalize(newSite)
        guard !domain.isEmpty, domain.contains(".") else { return }
        if !state.settings.guards.contains(where: { $0.kind == .website && $0.value == domain }) {
            state.settings.guards.append(GuardRule(kind: .website, value: domain, displayName: domain, mode: newSiteMode))
        }
        newSite = ""
    }

    // MARK: Timing

    private var timingSection: some View {
        Section {
            Stepper("Speed bump starts at \(state.settings.bumpBaseDelaySeconds)s", value: $state.settings.bumpBaseDelaySeconds, in: 3...60)
            Stepper("…plus \(state.settings.bumpDelayStepSeconds)s for each earlier open today", value: $state.settings.bumpDelayStepSeconds, in: 0...30)
            Stepper("…up to \(state.settings.bumpMaxDelaySeconds)s", value: $state.settings.bumpMaxDelaySeconds, in: 10...300, step: 5)
            Stepper("Speed bump reason: at least \(state.settings.bumpMinReasonLength) characters", value: $state.settings.bumpMinReasonLength, in: 0...200, step: 5)
            Stepper("Block wait: \(state.settings.blockDelaySeconds)s", value: $state.settings.blockDelaySeconds, in: 10...600, step: 10)
            Stepper("Block reason: at least \(state.settings.blockMinReasonLength) characters", value: $state.settings.blockMinReasonLength, in: 10...300, step: 10)
        } header: {
            Text("How hard it is to get through")
        }
    }

    // MARK: Tracking

    private var trackingSection: some View {
        Section {
            Toggle("Track which websites you're on (not just the browser)", isOn: $state.settings.trackBrowserDomains)
            Stepper(
                "Count me as away after \(state.settings.idleThresholdSeconds / 60) min without input",
                value: $state.settings.idleThresholdSeconds,
                in: 60...1800,
                step: 60
            )
        } header: {
            Text("Where did my day go?")
        } footer: {
            Text("Time with a video playing still counts even without input. Everything is stored only on this Mac.")
        }
    }

    private var summarySection: some View {
        Section {
            Toggle("Send an end-of-day summary", isOn: $state.settings.dailySummaryEnabled)
            DatePicker(
                "At",
                selection: minuteBinding($state.settings.dailySummaryMinute),
                displayedComponents: .hourAndMinute
            )
            .disabled(!state.settings.dailySummaryEnabled)
        } header: {
            Text("Daily summary")
        }
    }

    // MARK: Categories

    private var categoriesSection: some View {
        Section {
            let overrides = state.settings.categoryOverrides.sorted { $0.key < $1.key }
            if overrides.isEmpty {
                Text("No custom labels yet. Change them from the day report.")
                    .foregroundStyle(.secondary)
            }
            ForEach(overrides, id: \.key) { pair in
                let key = pair.key
                HStack {
                    Text(key.hasPrefix("domain:") ? String(key.dropFirst(7)) : appName(for: key))
                    Spacer()
                    Picker("Label", selection: Binding(
                        get: { pair.value },
                        set: { state.settings.categoryOverrides[key] = $0 }
                    )) {
                        ForEach(AppCategory.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    Button {
                        state.settings.categoryOverrides[key] = nil
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .help("Go back to the default label")
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Your labels")
        }
    }

    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: General

    private var generalSection: some View {
        Section {
            Toggle("Open Pause when I log in", isOn: Binding(
                get: { state.launchesAtLogin },
                set: { loginError = state.setLaunchesAtLogin($0) }
            ))
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.orange)
            }
            LabeledContent("Log an urge from anywhere", value: "⌥⌘U")
            Button("Show my data in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([state.store.root])
            }
        } header: {
            Text("General")
        } footer: {
            Text("Quitting Pause turns every guard off. Turning on \"Open Pause when I log in\" makes that harder to forget.")
        }
    }

    private func minuteBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        let calendar = state.calendar
        return Binding(
            get: {
                calendar.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = calendar.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}

/// One guarded app or site: mode, optional schedule, remove.
private struct GuardRow: View {
    @Binding var rule: GuardRule
    let onRemove: () -> Void

    private static let dayLetters = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 1) {
                    Text(rule.displayName)
                    Text(rule.kind == .website ? rule.value : "App")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Mode", selection: $rule.mode) {
                    ForEach(GuardMode.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 130)
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove this guard")
            }

            Toggle("Only at certain times", isOn: Binding(
                get: { rule.schedule != nil },
                set: { rule.schedule = $0 ? GuardSchedule(weekdays: Set(2...6)) : nil }
            ))
            .font(.callout)

            if rule.schedule != nil {
                HStack(spacing: 12) {
                    DatePicker("From", selection: scheduleBinding(\.startMinute), displayedComponents: .hourAndMinute)
                    DatePicker("to", selection: scheduleBinding(\.endMinute), displayedComponents: .hourAndMinute)
                    Spacer()
                }
                .font(.callout)
                HStack(spacing: 4) {
                    ForEach(1...7, id: \.self) { weekday in
                        let on = rule.schedule?.weekdays.contains(weekday) ?? false
                        Button(Self.dayLetters[weekday - 1]) { toggleDay(weekday) }
                            .buttonStyle(.bordered)
                            .tint(on ? Color.accentColor : Color.secondary)
                            .opacity(on ? 1 : 0.5)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var icon: some View {
        if rule.kind == .app, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.value) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: rule.kind == .website ? "globe" : "app")
                .frame(width: 24, height: 24)
        }
    }

    private func toggleDay(_ weekday: Int) {
        guard var schedule = rule.schedule else { return }
        if schedule.weekdays.contains(weekday) {
            schedule.weekdays.remove(weekday)
        } else {
            schedule.weekdays.insert(weekday)
        }
        rule.schedule = schedule
    }

    private func scheduleBinding(_ keyPath: WritableKeyPath<GuardSchedule, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minute = rule.schedule?[keyPath: keyPath] ?? 0
                return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                rule.schedule?[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}
