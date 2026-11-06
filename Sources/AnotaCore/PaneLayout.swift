import Foundation
import CoreGraphics

public enum SplitDirection: String, Codable, Sendable, CaseIterable, Identifiable {
    case left, right, top, bottom
    public var id: Self { self }
    public var title: String { rawValue.capitalized }
    public var horizontal: Bool { self == .left || self == .right }
    public var before: Bool { self == .left || self == .top }

    public static func edge(at point: CGPoint, in rect: CGRect) -> Self? {
        guard rect.width > 0, rect.height > 0, rect.contains(point) else { return nil }
        let distances: [(Self, CGFloat)] = [
            (.left, (point.x - rect.minX) / min(160, rect.width / 4)),
            (.right, (rect.maxX - point.x) / min(160, rect.width / 4)),
            (.top, (point.y - rect.minY) / min(160, rect.height / 4)),
            (.bottom, (rect.maxY - point.y) / min(160, rect.height / 4))
        ]
        guard let nearest = distances.min(by: { $0.1 < $1.1 }), nearest.1 <= 1 else { return nil }
        return nearest.0
    }
}

/// A binary layout keeps each split local to its pane and allows mixed horizontal/vertical splits.
public indirect enum PaneLayout: Codable, Sendable, Equatable {
    case leaf(UUID)
    case split(id: UUID, horizontal: Bool, ratio: Double, first: PaneLayout, second: PaneLayout)

    public var leaves: [UUID] {
        switch self {
        case .leaf(let id): [id]
        case .split(_, _, _, let first, let second): first.leaves + second.leaves
        }
    }

    public func inserting(_ new: UUID, beside target: UUID, direction: SplitDirection) -> Self {
        switch self {
        case .leaf(let id):
            guard id == target else { return self }
            return .split(id: UUID(), horizontal: direction.horizontal, ratio: 0.5,
                          first: direction.before ? .leaf(new) : self,
                          second: direction.before ? self : .leaf(new))
        case .split(let id, let horizontal, let ratio, let first, let second):
            return .split(id: id, horizontal: horizontal, ratio: ratio,
                          first: first.inserting(new, beside: target, direction: direction),
                          second: second.inserting(new, beside: target, direction: direction))
        }
    }

    public func retaining(_ ids: Set<UUID>) -> Self? {
        switch self {
        case .leaf(let id): return ids.contains(id) ? self : nil
        case .split(let id, let horizontal, let ratio, let first, let second):
            let a = first.retaining(ids), b = second.retaining(ids)
            if let a, let b { return .split(id: id, horizontal: horizontal, ratio: ratio, first: a, second: b) }
            return a ?? b
        }
    }

    public func resizing(_ target: UUID, ratio newRatio: Double) -> Self {
        switch self {
        case .leaf: return self
        case .split(let id, let horizontal, let ratio, let first, let second):
            return .split(id: id, horizontal: horizontal,
                          ratio: id == target && newRatio.isFinite ? min(max(newRatio, 0.05), 0.95) : ratio,
                          first: first.resizing(target, ratio: newRatio), second: second.resizing(target, ratio: newRatio))
        }
    }

    public static func row(_ ids: [UUID]) -> Self {
        precondition(!ids.isEmpty)
        guard ids.count > 1 else { return .leaf(ids[0]) }
        return .split(id: UUID(), horizontal: true, ratio: 1 / Double(ids.count),
                      first: .leaf(ids[0]), second: row(Array(ids.dropFirst())))
    }
}
