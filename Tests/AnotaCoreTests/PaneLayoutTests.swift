import Foundation
import Testing
@testable import AnotaCore

@Test(arguments: SplitDirection.allCases)
func paneLayoutInsertsInEveryDirection(_ direction: SplitDirection) throws {
    let original = UUID(), new = UUID()
    let layout = PaneLayout.leaf(original).inserting(new, beside: original, direction: direction)
    guard case .split(let id, let horizontal, let ratio, _, _) = layout else { Issue.record("Expected split"); return }
    #expect(horizontal == direction.horizontal)
    #expect(ratio == 0.5)
    #expect(layout.leaves == (direction.before ? [new, original] : [original, new]))
    #expect(layout.retaining([original]) == .leaf(original))
    #expect(try JSONDecoder().decode(PaneLayout.self, from: JSONEncoder().encode(layout)) == layout)
    guard case .split(_, _, let resized, _, _) = layout.resizing(id, ratio: 0.7) else { return }
    #expect(resized == 0.7)
}

@Test func mixedLayoutCollapsesOnlyRemovedBranch() {
    let a = UUID(), b = UUID(), c = UUID()
    let layout = PaneLayout.leaf(a).inserting(b, beside: a, direction: .right).inserting(c, beside: b, direction: .bottom)
    #expect(layout.leaves == [a, b, c])
    let kept = layout.retaining([a, c])
    #expect(kept?.leaves == [a, c])
    guard case .split(_, let horizontal, _, _, let second)? = kept else { Issue.record("Missing outer split"); return }
    #expect(horizontal)
    #expect(second == .leaf(c))
}

@Test func edgeDropZonesLeaveCenterAlone() {
    let frame = CGRect(x: 100, y: 100, width: 600, height: 400)
    #expect(SplitDirection.edge(at: CGPoint(x: 110, y: 300), in: frame) == .left)
    #expect(SplitDirection.edge(at: CGPoint(x: 690, y: 300), in: frame) == .right)
    #expect(SplitDirection.edge(at: CGPoint(x: 400, y: 110), in: frame) == .top)
    #expect(SplitDirection.edge(at: CGPoint(x: 400, y: 490), in: frame) == .bottom)
    #expect(SplitDirection.edge(at: CGPoint(x: 400, y: 300), in: frame) == nil)
    #expect(SplitDirection.edge(at: CGPoint(x: 0, y: 0), in: frame) == nil)
}

@Test func legacySessionDecodesWithoutLayoutOrGroupIDs() throws {
    let json = """
    {"tabs":[],"groups":[{"tabs":[]}],"focused":0,"verticalTabs":false,"wrap":false}
    """
    let session = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
    #expect(session.layout == nil)
    #expect(session.groups.first?.id == nil)
}
