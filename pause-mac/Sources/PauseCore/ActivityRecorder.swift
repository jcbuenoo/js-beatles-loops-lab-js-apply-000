import Foundation

/// Turns a stream of "what's frontmost right now" samples into time spans.
///
/// Feed it a sample on every tick and every app switch; pass `nil` while you're idle, asleep or locked.
public struct ActivityRecorder {
    public private(set) var current: ActivitySpan?
    private var closed: [ActivitySpan] = []
    /// A tick arriving later than this after the previous one (e.g. after sleep) starts a fresh span
    /// instead of claiming the missing time.
    public var maxGap: TimeInterval

    public init(maxGap: TimeInterval = 30) {
        self.maxGap = maxGap
    }

    public mutating func observe(_ sample: ActivitySample?, at now: Date) {
        if var cur = current {
            let contiguous = now >= cur.end && now.timeIntervalSince(cur.end) <= maxGap
            if contiguous { cur.end = now }
            if let sample, contiguous, sample.key == cur.key {
                current = cur
                return
            }
            close(cur)
            current = nil
        }
        if let sample {
            current = ActivitySpan(start: now, end: now, sample: sample)
        }
    }

    /// Everything not yet handed out, including the open span. Doesn't change state.
    public func pending() -> [ActivitySpan] {
        var spans = closed
        if let current, current.duration > 0 { spans.append(current) }
        return spans
    }

    /// Hands out finished spans for saving. With `includeOpen`, the open span's time so far is handed
    /// out too and the open span continues from where that piece ended, so a crash loses at most one tick.
    public mutating func drain(includeOpen: Bool) -> [ActivitySpan] {
        var spans = closed
        closed = []
        if includeOpen, var cur = current, cur.duration > 0 {
            spans.append(cur)
            cur.start = cur.end
            current = cur
        }
        return spans
    }

    private mutating func close(_ span: ActivitySpan) {
        if span.duration >= 1 { closed.append(span) }
    }
}
