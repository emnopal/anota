import AnotaCore
import SwiftUI
import WebKit

/// swift-markdown → HTML in a WKWebView. Relative images resolve against the file's folder;
/// clicked links open in the default browser. Scroll position is kept across re-renders.
struct MarkdownPreview: NSViewRepresentable {
    let buffer: Buffer
    let revision: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        Self.makeWebView(coordinator: context.coordinator)
    }

    static func makeWebView(coordinator: Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = coordinator
        web.underPageBackgroundColor = .textBackgroundColor
        web.setValue(false, forKey: "drawsBackground")
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        update(web, coordinator: context.coordinator)
    }

    func update(_ web: WKWebView, coordinator c: Coordinator) {
        guard c.revision != revision || c.buffer !== buffer else { return }
        c.revision = revision
        c.buffer = buffer
        let html = MarkdownHTML.page(buffer.text)
        let base = buffer.url?.deletingLastPathComponent()
        web.evaluateJavaScript("window.scrollY", in: nil, in: .defaultClient) { y in
            guard c.revision == revision, c.buffer === buffer else { return }
            c.pendingLoad = true
            c.restoreY = (try? y.get() as? Double) ?? 0
            web.loadHTMLString(html, baseURL: base)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var revision = -1
        weak var buffer: Buffer?
        var restoreY = 0.0
        var pendingLoad = false

        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            web.evaluateJavaScript("window.scrollTo(0, \(restoreY))", in: nil, in: .defaultClient)
        }

        func webView(_ web: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                if ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel)
            } else {
                let initial = pendingLoad && action.navigationType == .other
                pendingLoad = false
                decisionHandler(initial ? .allow : .cancel)
            }
        }
    }
}
