import Foundation

/// Turns raw modifier press/release edges into recording start/stop.
///
/// - `hold`: press starts, release stops (push-to-talk).
/// - `toggle`: two taps within `doubleTapWindow` start recording; a single
///   tap while recording stops it. A lone tap does nothing.
final class HotkeyGestureInterpreter {
    enum Mode {
        case hold
        case toggle
    }

    static let defaultDoubleTapWindow: TimeInterval = 0.4

    private let mode: Mode
    private let doubleTapWindow: TimeInterval
    private let now: () -> Date

    private var isRecording = false
    private var lastReleaseAt: Date?
    /// After a press stops a toggle session, ignore that key's matching release
    /// so it cannot count as the first tap of a new double-tap.
    private var consumeNextRelease = false

    init(
        mode: Mode,
        doubleTapWindow: TimeInterval = defaultDoubleTapWindow,
        now: @escaping () -> Date = Date.init
    ) {
        self.mode = mode
        self.doubleTapWindow = doubleTapWindow
        self.now = now
    }

    /// Recording event to fire, or `nil` if this edge should be ignored.
    func handle(_ event: HotkeyMonitor.Event) -> HotkeyMonitor.Event? {
        switch mode {
        case .hold:
            return event
        case .toggle:
            return handleToggle(event)
        }
    }

    private func handleToggle(_ event: HotkeyMonitor.Event) -> HotkeyMonitor.Event? {
        switch event {
        case .pressed:
            guard isRecording else { return nil }
            isRecording = false
            lastReleaseAt = nil
            consumeNextRelease = true
            return .released
        case .released:
            if consumeNextRelease {
                consumeNextRelease = false
                return nil
            }
            let t = now()
            if let last = lastReleaseAt, t.timeIntervalSince(last) <= doubleTapWindow {
                lastReleaseAt = nil
                isRecording = true
                return .pressed
            }
            lastReleaseAt = t
            return nil
        }
    }
}
