import AppKit

// Screen geometry as pure functions: slots, frames, nearest-slot snapping, edge bands.

/// One of the 19 card cells of the invisible 5 × 4 grid, numbered in pop order
/// (left → right, top → bottom). The bottom-right cell belongs to the stack and is not a `Slot`,
/// so no transition can ever put a card there.
struct Slot: Hashable, Comparable {
    static let columns = 5
    static let rows = 4
    static let count = columns * rows - 1
    /// Every slot in pop order; `Desk.firstFreeSlot` takes the first free one.
    static let all: [Slot] = (0..<count).map { Slot(unchecked: $0) }

    /// 0..<19 in reading order.
    let index: Int
    var column: Int { index % Slot.columns }
    var row: Int { index / Slot.columns }

    /// Boundary initializer for sidecar data: nil outside 0..<19 (19 would be the stack's cell).
    init?(index: Int) {
        guard (0..<Slot.count).contains(index) else { return nil }
        self.index = index
    }

    private init(unchecked index: Int) { self.index = index }

    static func < (a: Slot, b: Slot) -> Bool { a.index < b.index }
}

/// Grid geometry for one screen. The desk stores slots, never frames, so a display change is a
/// new `Grid` plus a re-render: every card re-snaps to its slot with no model change.
struct Grid: Equatable {
    /// The screen below the menu bar, in AppKit screen coordinates (origin bottom-left, y up).
    let area: CGRect

    init(area: CGRect) { self.area = area }

    /// The area below the menu bar of `screen` (the menu-bar screen). The Dock is deliberately
    /// not subtracted: the spec sizes cards from "screen height below menu bar".
    init?(screen: NSScreen?) {
        guard let screen else { return nil }
        let frame = screen.frame
        area = CGRect(x: frame.minX, y: frame.minY,
                      width: frame.width, height: screen.visibleFrame.maxY - frame.minY)
    }

    func frame(of slot: Slot) -> CGRect { cell(column: slot.column, row: slot.row) }

    var stackFrame: CGRect { cell(column: Slot.columns - 1, row: Slot.rows - 1) }

    /// The slot whose center is nearest `point` (a dropped card's center). Never the stack cell,
    /// because the stack cell is not a `Slot`.
    func nearestSlot(to point: CGPoint) -> Slot {
        func distance(_ slot: Slot) -> CGFloat {
            let f = frame(of: slot)
            return hypot(f.midX - point.x, f.midY - point.y)
        }
        return Slot.all.dropFirst().reduce(Slot.all[0]) { best, slot in
            distance(slot) < distance(best) ? slot : best
        }
    }

    /// Edges are rounded to whole points and shared with the neighbour, so cells tile the area
    /// exactly, with no gaps or overlaps, even when width / 5 is fractional (1512 / 5 = 302.4).
    private func cell(column: Int, row: Int) -> CGRect {
        let w = area.width / CGFloat(Slot.columns)
        let h = area.height / CGFloat(Slot.rows)
        let left = (area.minX + CGFloat(column) * w).rounded()
        let right = (area.minX + CGFloat(column + 1) * w).rounded()
        let top = (area.maxY - CGFloat(row) * h).rounded()
        let bottom = (area.maxY - CGFloat(row + 1) * h).rounded()
        return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
    }
}

/// An edge of the stack window, for its invisible flipping bands.
enum Edge: CaseIterable {
    case left, top, right, bottom

    /// Left/top swap in the previous stacked card; right/bottom the next.
    var direction: Direction {
        switch self {
        case .left, .top: .previous
        case .right, .bottom: .next
        }
    }
}

enum EdgeBands {
    /// Band depth: 5 % of the window's width (left/right bands) or height (top/bottom bands).
    static let fraction: CGFloat = 0.05

    /// The band containing `point` (window-local coordinates, y up), or nil. In a corner, where
    /// two bands overlap, the edge the point is relatively closer to wins, so every point has at
    /// most one meaning. Callers ask only when there is something to flip (`StackFace.canFlip`).
    static func edge(at point: CGPoint, in bounds: CGRect) -> Edge? {
        guard bounds.contains(point) else { return nil }
        let bandX = bounds.width * fraction
        let bandY = bounds.height * fraction
        let depth: [(edge: Edge, depth: CGFloat)] = [
            (.left, (point.x - bounds.minX) / bandX),
            (.right, (bounds.maxX - point.x) / bandX),
            (.bottom, (point.y - bounds.minY) / bandY),
            (.top, (bounds.maxY - point.y) / bandY),
        ]
        return depth.filter { $0.depth < 1 }.min { $0.depth < $1.depth }?.edge
    }

    /// The area of one band, for drawing its hover tint.
    static func rect(of edge: Edge, in bounds: CGRect) -> CGRect {
        let bandX = bounds.width * fraction
        let bandY = bounds.height * fraction
        return switch edge {
        case .left: CGRect(x: bounds.minX, y: bounds.minY, width: bandX, height: bounds.height)
        case .right: CGRect(x: bounds.maxX - bandX, y: bounds.minY, width: bandX, height: bounds.height)
        case .top: CGRect(x: bounds.minX, y: bounds.maxY - bandY, width: bounds.width, height: bandY)
        case .bottom: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bandY)
        }
    }
}
