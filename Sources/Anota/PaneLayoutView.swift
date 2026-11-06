import AnotaCore
import SwiftUI

struct PaneLayoutView: View {
    let ws: Workspace
    let node: PaneLayout
    var selectionID: UUID?

    var body: AnyView {
        switch node {
        case .leaf(let id):
            return AnyView(Group {
                if let group = ws.groups.first(where: { $0.id == id }) {
                    GroupView(ws: ws, group: group).id(id)
                }
            })
        case .split(let id, let horizontal, let ratio, let first, let second):
            return AnyView(PaneBranch(ws: ws, id: id, horizontal: horizontal, ratio: ratio,
                                      first: first, second: second, selectionID: selectionID).id(id))
        }
    }
}

private struct PaneBranch: View {
    let ws: Workspace
    let id: UUID
    let horizontal: Bool
    let ratio: Double
    let first: PaneLayout
    let second: PaneLayout
    let selectionID: UUID?
    @State private var startRatio: Double?

    var body: some View {
        GeometryReader { geometry in
            let available = max((horizontal ? geometry.size.width : geometry.size.height) - 1, 1)
            let fraction = ratio.isFinite ? min(max(ratio, 0.05), 0.95) : 0.5
            if horizontal {
                HStack(spacing: 0) {
                    child(first, extent: available * fraction)
                    divider(available: available)
                    child(second, extent: available * (1 - fraction))
                }
            } else {
                VStack(spacing: 0) {
                    child(first, extent: available * fraction)
                    divider(available: available)
                    child(second, extent: available * (1 - fraction))
                }
            }
        }
    }

    private func child(_ node: PaneLayout, extent: CGFloat) -> some View {
        PaneLayoutView(ws: ws, node: node, selectionID: selectionID)
            .frame(width: horizontal ? extent : nil, height: horizontal ? nil : extent)
    }

    private func divider(available: CGFloat) -> some View {
        Rectangle().fill(Color(nsColor: .separatorColor))
            .frame(width: horizontal ? 1 : nil, height: horizontal ? nil : 1)
            .overlay {
                Color.clear
                    .frame(width: horizontal ? 9 : nil, height: horizontal ? nil : 9)
                    .contentShape(Rectangle())
                    .pointerStyle(horizontal ? .columnResize : .rowResize)
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let start = startRatio ?? ratio
                            startRatio = start
                            let delta = horizontal ? value.translation.width : value.translation.height
                            let minimum = min((horizontal ? 220.0 : 120.0) / available, 0.5)
                            ws.resizeSplit(id, ratio: min(max(start + delta / available, minimum), 1 - minimum))
                        }
                        .onEnded { _ in startRatio = nil })
            }
    }
}
