import AppKit

// Screen geometry as pure functions: slots, free positions, snapping, frames, edge bands.

/// One of the 20 cells of the invisible 5 × 4 grid, numbered in pop order (left → right,
/// top → bottom). The stack takes one like a card does, top-left until it is moved.
struct Slot: Hashable, Comparable {
    static let columns = 5
    static let rows = 4
    static let count = columns * rows
    /// Every slot in pop order; `Desk.firstFreeSlot` takes the first free one.
    static let all: [Slot] = (0..<count).map { Slot(unchecked: $0) }

    /// 0..<20 in reading order.
    let index: Int
    var column: Int { index % Slot.columns }
    var row: Int { index / Slot.columns }

    /// Boundary initializer for sidecar data: nil outside 0..<20.
    init?(index: Int) {
        guard (0..<Slot.count).contains(index) else { return nil }
        self.index = index
    }

    private init(unchecked index: Int) { self.index = index }

    /// The cell containing `point`. A card is exactly one cell in size, so this is also the cell
    /// a card centered at `point` covers most, and the one whose center is nearest.
    init(containing point: GridPoint) {
        let column = min(Int(point.x * Double(Slot.columns)), Slot.columns - 1)
        let row = min(Int(point.y * Double(Slot.rows)), Slot.rows - 1)
        index = row * Slot.columns + column
    }

    /// The cell's center.
    var center: GridPoint {
        GridPoint(x: (Double(column) + 0.5) / Double(Slot.columns), y: (Double(row) + 0.5) / Double(Slot.rows))
    }

    static func < (a: Slot, b: Slot) -> Bool { a.index < b.index }
}

/// The center of a card-sized item as a fraction of the grid area, from the top-left (x right,
/// y down), so a display change rescales it with no model change. Always far enough from the
/// edges that the whole item is on screen: every initializer clamps, the decoder included.
struct GridPoint: Hashable, Codable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        let halfWidth = 0.5 / Double(Slot.columns)
        let halfHeight = 0.5 / Double(Slot.rows)
        self.x = x.isFinite ? min(max(x, halfWidth), 1 - halfWidth) : 0.5
        self.y = y.isFinite ? min(max(y, halfHeight), 1 - halfHeight) : 0.5
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(x: try c.decode(Double.self, forKey: .x), y: try c.decode(Double.self, forKey: .y))
    }
}

/// Where a card or the stack is on the desktop: snapped to a slot, or free at a point.
enum Place: Hashable {
    case slot(Slot)
    case free(GridPoint)

    /// How close a drop must land to a slot's center to snap: 15 % of a cell, measured in cell
    /// widths and heights.
    static let snapDistance = 0.15

    /// The slot this place takes for Pop: its own slot, or the one a free item covers most.
    var slot: Slot {
        switch self {
        case .slot(let slot): slot
        case .free(let point): Slot(containing: point)
        }
    }

    /// What the drag guide shows for an item centered at `point`: the slot a drop there would
    /// snap to, and whether it would.
    static func guide(at point: GridPoint) -> (slot: Slot, snaps: Bool) {
        let slot = Slot(containing: point)
        let dx = (point.x - slot.center.x) * Double(Slot.columns)
        let dy = (point.y - slot.center.y) * Double(Slot.rows)
        return (slot, hypot(dx, dy) <= snapDistance)
    }

    /// Where an item dropped with its center at `point` lands: slid fully on screen, then snapped
    /// to the nearest slot if close enough, otherwise free right there.
    static func dropped(at point: GridPoint) -> Place {
        let guide = guide(at: point)
        return guide.snaps ? .slot(guide.slot) : .free(point)
    }
}

/// Grid geometry for one screen. The desk stores places, never frames, so a display change is a
/// new `Grid` plus a re-render: every card goes back to its place with no model change.
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

    func frame(of place: Place) -> CGRect {
        switch place {
        case .slot(let slot):
            return frame(of: slot)
        case .free(let point):
            let w = area.width / CGFloat(Slot.columns)
            let h = area.height / CGFloat(Slot.rows)
            let midX = area.minX + CGFloat(point.x) * area.width
            let midY = area.maxY - CGFloat(point.y) * area.height
            return CGRect(x: (midX - w / 2).rounded(), y: (midY - h / 2).rounded(), width: w.rounded(), height: h.rounded())
        }
    }

    /// `screenPoint` (a dragged window's center) as a grid point, clamped on screen.
    func point(at screenPoint: CGPoint) -> GridPoint {
        GridPoint(x: Double((screenPoint.x - area.minX) / area.width),
                  y: Double((area.maxY - screenPoint.y) / area.height))
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
    /// most one meaning.
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
