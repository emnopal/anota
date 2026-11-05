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
        let web = WKWebView()
        web.navigationDelegate = context.coordinator
        web.underPageBackgroundColor = .textBackgroundColor
        web.setValue(false, forKey: "drawsBackground")
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        let c = context.coordinator
        guard c.revision != revision || c.buffer !== buffer else { return }
        c.revision = revision
        c.buffer = buffer
        let html = MarkdownHTML.page(buffer.text)
        let base = buffer.url?.deletingLastPathComponent()
        web.evaluateJavaScript("window.scrollY") { y, _ in
            c.restoreY = (y as? Double) ?? 0
            web.loadHTMLString(html, baseURL: base)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var revision = -1
        weak var buffer: Buffer?
        var restoreY = 0.0

        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            web.evaluateJavaScript("window.scrollTo(0, \(restoreY))")
        }

        func webView(_ web: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
