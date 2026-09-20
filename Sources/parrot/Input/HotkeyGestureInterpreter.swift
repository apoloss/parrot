import Foundation

/// Turns raw modifier press/release edges into recording start/stop.
///
/// - `hold`: press starts, release stops (push-to-talk).
/// - `toggle`: hold still push-to-talks; two short taps within `doubleTapWindow`
///   latch recording on, and a later tap unlatches. A lone short tap cancels
///   so it does not transcribe.
final class HotkeyGestureInterpreter {
    enum Mode {
        case hold
        case toggle
    }

    static let defaultDoubleTapWindow: TimeInterval = 0.4
    /// Presses shorter than this are taps (double-tap / cancel), not PTT.
    static let defaultHoldThreshold: TimeInterval = 0.2

    private let mode: Mode
    private let doubleTapWindow: TimeInterval
    private let holdThreshold: TimeInterval
    private let now: () -> Date

    private var isRecording = false
    private var isLatched = false
    private var pressAt: Date?
    private var lastTapAt: Date?
    /// After a press stops a latched session, ignore that key's matching release
    /// so it cannot count as the first tap of a new double-tap.
    private var consumeNextRelease = false

    init(
        mode: Mode,
        doubleTapWindow: TimeInterval = defaultDoubleTapWindow,
        holdThreshold: TimeInterval = defaultHoldThreshold,
        now: @escaping () -> Date = Date.init
    ) {
        self.mode = mode
        self.doubleTapWindow = doubleTapWindow
        self.holdThreshold = holdThreshold
        self.now = now
    }

    /// Recording event to fire, or `nil` if this edge should be ignored.
    func handle(_ event: HotkeyMonitor.Event) -> HotkeyMonitor.Event? {
        switch mode {
        case .hold:
            return event
        case .toggle:
            return handleCombined(event)
        }
    }

    private func handleCombined(_ event: HotkeyMonitor.Event) -> HotkeyMonitor.Event? {
        switch event {
        case .pressed:
            if isRecording {
                isRecording = false
                isLatched = false
                pressAt = nil
                lastTapAt = nil
                consumeNextRelease = true
                return .released
            }
            isRecording = true
            pressAt = now()
            return .pressed
        case .released:
            if consumeNextRelease {
                consumeNextRelease = false
                return nil
            }
            guard isRecording, !isLatched else { return nil }
            let t = now()
            let duration = pressAt.map { t.timeIntervalSince($0) } ?? 0
            pressAt = nil

            if duration >= holdThreshold {
                isRecording = false
                lastTapAt = nil
                return .released
            }

            if let last = lastTapAt, t.timeIntervalSince(last) <= doubleTapWindow {
                isLatched = true
                lastTapAt = nil
                return nil
            }

            isRecording = false
            lastTapAt = t
            return .cancelled
        case .cancelled:
            return nil
        }
    }
}
