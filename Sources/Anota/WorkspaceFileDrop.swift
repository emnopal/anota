import AnotaCore
import SwiftUI
import UniformTypeIdentifiers

/// Use the same edge zones for file drags as for tabs; center drops open in the existing pane.
struct WorkspaceFileDrop: DropDelegate {
    let ws: Workspace
    let group: EditorGroup
    var allowSplit = true

    private func direction(_ info: DropInfo) -> SplitDirection? {
        guard allowSplit, let frame = ws.paneFrames[group.id] else { return nil }
        return SplitDirection.edge(at: info.location, in: CGRect(origin: .zero, size: frame.size))
    }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [UTType.fileURL]) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let edge = direction(info).map { Workspace.SplitDrop(groupID: group.id, direction: $0) }
        if ws.splitDrop != edge { ws.splitDrop = edge }
        let center = edge == nil ? Workspace.TabDrop(groupID: group.id, beforeID: nil, after: false) : nil
        if ws.tabDrop != center { ws.tabDrop = center }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        if ws.splitDrop?.groupID == group.id { ws.splitDrop = nil }
        if ws.tabDrop?.groupID == group.id { ws.tabDrop = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [UTType.fileURL])
        guard !providers.isEmpty else { return false }
        let edge = direction(info)
        ws.splitDrop = nil
        ws.tabDrop = nil
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                let data: Data? = await withCheckedContinuation { continuation in
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                        continuation.resume(returning: data)
                    }
                }
                if let data, let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
                    urls.append(url)
                }
            }
            ws.dropFiles(urls, in: group, direction: edge)
        }
        return true
    }
}
