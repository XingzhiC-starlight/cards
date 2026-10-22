import AppKit

/// Reads the scroll events over the stack and decides, one event at a time, whether the text
/// should scroll, the event should be swallowed, or the stack should flip. Events come in as
/// numbers, so the rules are testable without AppKit windows.
///
/// A trackpad gesture is `phase` `.began` … `.ended`, then its inertia arrives as events with an
/// empty `phase` and a `momentumPhase`. The first non-trivial movement locks the axis for the
/// whole gesture and its momentum. Vertical movement belongs to the text, so every event passes
/// through. Horizontal movement belongs to the stack: every event is swallowed, and the stack
/// flips once, when the gesture has travelled `flipDistance`. A mouse wheel has no phases: a
/// horizontal-dominant event flips at once, then horizontal events are ignored for `wheelPause`.
///
/// Deltas are `scrollingDeltaX` / `scrollingDeltaY` as delivered, which already follow the
/// system's scroll direction. Fingers moving right (positive) show the previous card, moving
/// left (negative) the next.
struct SwipeTracker {
    enum Verdict: Equatable {
        /// Hand the event to the window as usual (the text scrolls).
        case pass
        /// Part of a swipe that already flipped or will: do not scroll anything.
        case consume
        case flip(Direction)
    }

    static let flipDistance: CGFloat = 30
    static let lockDistance: CGFloat = 1
    static let wheelPause: TimeInterval = 0.3

    private enum Axis { case undecided, vertical, horizontal }

    private var axis = Axis.undecided
    private var travelled = CGVector.zero
    private var flipped = false
    private var lastWheelFlip: TimeInterval?

    mutating func feed(phase: NSEvent.Phase, momentumPhase: NSEvent.Phase,
                       deltaX: CGFloat, deltaY: CGFloat, at time: TimeInterval) -> Verdict {
        if phase.isEmpty, momentumPhase.isEmpty { return wheel(deltaX, deltaY, at: time) }
        if phase.contains(.mayBegin) || phase.contains(.began) {
            axis = .undecided
            travelled = .zero
            flipped = false
        }
        if !momentumPhase.isEmpty { return axis == .horizontal ? .consume : .pass }
        switch axis {
        case .undecided:
            travelled.dx += deltaX
            travelled.dy += deltaY
            if max(abs(travelled.dx), abs(travelled.dy)) >= Self.lockDistance {
                axis = abs(travelled.dx) > abs(travelled.dy) ? .horizontal : .vertical
            }
        case .horizontal:
            travelled.dx += deltaX
        case .vertical:
            break
        }
        guard axis == .horizontal else { return .pass }
        if !flipped, abs(travelled.dx) >= Self.flipDistance {
            flipped = true
            return .flip(travelled.dx > 0 ? .previous : .next)
        }
        return .consume
    }

    private mutating func wheel(_ deltaX: CGFloat, _ deltaY: CGFloat, at time: TimeInterval) -> Verdict {
        guard abs(deltaX) > abs(deltaY) else { return .pass }
        if let last = lastWheelFlip, time - last < Self.wheelPause { return .consume }
        lastWheelFlip = time
        return .flip(deltaX > 0 ? .previous : .next)
    }
}
