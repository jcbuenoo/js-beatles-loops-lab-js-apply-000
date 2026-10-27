import AppKit
import PauseCore
import SwiftUI

/// Borderless windows can't take keyboard focus unless they say so; the reason field needs it.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Covers every screen while a speed bump or block screen is up.
@MainActor
final class GuardOverlayController {
    private var windows: [NSWindow] = []
    private let model: GuardViewModel

    init(rule: GuardRule, requirements: GuardRequirements, opensToday: Int, onDecision: @escaping (GuardDecision) -> Void) {
        model = GuardViewModel(rule: rule, requirements: requirements, opensToday: opensToday, onDecision: onDecision)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        let mainScreen = NSScreen.main ?? NSScreen.screens.first
        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.setFrame(screen.frame, display: true)
            if screen == mainScreen {
                window.contentView = NSHostingView(rootView: GuardView(model: model))
                window.makeKeyAndOrderFront(nil)
            } else {
                window.contentView = NSHostingView(rootView: DimView())
                window.orderFrontRegardless()
            }
            windows.append(window)
        }
        model.start()
    }

    func close() {
        model.stop()
        let closing = windows
        closing.forEach { $0.orderOut(nil) }
        // Free the views after the button tap that closed them has finished.
        Task { @MainActor in closing.forEach { $0.contentView = nil } }
        windows = []
    }
}

@MainActor
final class GuardViewModel: ObservableObject {
    let rule: GuardRule
    let requirements: GuardRequirements
    let opensToday: Int
    @Published var reason = ""
    @Published private(set) var remaining: Int
    private let onDecision: (GuardDecision) -> Void
    private var countdown: Task<Void, Never>?
    private var decided = false

    init(rule: GuardRule, requirements: GuardRequirements, opensToday: Int, onDecision: @escaping (GuardDecision) -> Void) {
        self.rule = rule
        self.requirements = requirements
        self.opensToday = opensToday
        self.onDecision = onDecision
        remaining = requirements.waitSeconds
    }

    var elapsed: Int { requirements.waitSeconds - remaining }
    var isBlock: Bool { rule.mode == .block }

    var title: String {
        isBlock ? "\(rule.displayName) is blocked" : "Pause before \(rule.displayName)"
    }

    var subtitle: String {
        if isBlock {
            var s = rule.schedule.map { "Blocked \($0.summary)." } ?? "Blocked all the time."
            s += " Unlocking takes \(requirements.waitSeconds) seconds and a real reason, and only lasts a few minutes."
            return s
        }
        switch opensToday {
        case 0: return "First time today. Take a breath first."
        case 1: return "Second time today. The wait gets a little longer each time."
        default: return "You've been here \(opensToday) times today. This wait is \(requirements.waitSeconds) seconds."
        }
    }

    var prompt: String {
        isBlock ? "Why do you need \(rule.displayName) right now?" : "Why are you opening \(rule.displayName)?"
    }

    var placeholder: String {
        isBlock ? "Explain it like you would to a friend who's helping you stay on track…" : "Be specific: what will you do there?"
    }

    var hint: String {
        if let problem = GuardPolicy.reasonProblem(reason, requirements) { return problem }
        return remaining > 0 ? "Good reason. You can continue in \(remaining)s." : "Ready when you are."
    }

    var canProceed: Bool {
        remaining == 0 && GuardPolicy.isReasonAcceptable(reason, requirements)
    }

    func start() {
        countdown?.cancel()
        guard remaining > 0 else { return }
        countdown = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.remaining = max(0, self.remaining - 1)
                if self.remaining == 0 { return }
            }
        }
    }

    func stop() {
        countdown?.cancel()
        countdown = nil
    }

    func backOff() {
        guard !decided else { return }
        decided = true
        onDecision(.backedOff(reason: reason, waited: elapsed))
    }

    func proceed(minutes: Int) {
        guard !decided, canProceed else { return }
        decided = true
        onDecision(.proceed(minutes: minutes, reason: reason, waited: elapsed))
    }
}

struct GuardView: View {
    @ObservedObject var model: GuardViewModel
    @FocusState private var reasonFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 26) {
                VStack(spacing: 10) {
                    Image(systemName: model.isBlock ? "hand.raised.fill" : "pause.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(model.isBlock ? Color.orange : Color.teal)
                    Text(model.title)
                        .font(.system(size: 32, weight: .semibold))
                    Text(model.subtitle)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)
                }

                BreathingCircle(remaining: model.remaining, elapsed: model.elapsed)

                VStack(alignment: .leading, spacing: 8) {
                    Text(model.prompt).font(.headline)
                    TextField(model.placeholder, text: $model.reason, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .lineLimit(2...5)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.1)))
                        .focused($reasonFocused)
                    Text(model.hint)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(width: 560)

                HStack(spacing: 12) {
                    Button {
                        model.backOff()
                    } label: {
                        Text("Never mind").frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .keyboardShortcut(.cancelAction)

                    ForEach(model.requirements.unlockMinutes, id: \.self) { minutes in
                        Button("Open for \(minutes) min") { model.proceed(minutes: minutes) }
                            .buttonStyle(.bordered)
                            .disabled(!model.canProceed)
                    }
                }
                .controlSize(.large)

                Text("Your answer is saved to your urge log either way.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .foregroundStyle(.white)
            .padding(40)
        }
        .environment(\.colorScheme, .dark)
        .onAppear { reasonFocused = true }
    }
}

/// Grows on the in-breath and shrinks on the out-breath (4 seconds each), with the countdown inside.
struct BreathingCircle: View {
    let remaining: Int
    let elapsed: Int

    @State private var appeared = false

    private var breathingIn: Bool { (elapsed / 4) % 2 == 0 }

    private var scale: CGFloat {
        if remaining == 0 { return 1 }
        return appeared && breathingIn ? 1.0 : 0.6
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.teal.opacity(0.25))
                .frame(width: 150, height: 150)
                .scaleEffect(scale)
                .animation(.easeInOut(duration: 4), value: scale)
            VStack(spacing: 4) {
                Text(remaining > 0 ? "\(remaining)" : "✓")
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .monospacedDigit()
                Text(remaining > 0 ? (breathingIn ? "breathe in" : "breathe out") : "you waited")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: 170, height: 170)
        .onAppear { appeared = true }
    }
}

struct DimView: View {
    var body: some View {
        Color.black.opacity(0.88).ignoresSafeArea()
    }
}
