import AnotaCore
import SwiftUI
import WebKit

/// swift-markdown → HTML in a WKWebView. Relative images resolve against the file's folder;
/// clicked links open in the default browser. Scroll position is kept across re-renders.
struct MarkdownPreview: NSViewRepresentable {
    let buffer: Buffer
    let revision: Int
    // Capture during body evaluation so scroll-only changes invalidate the representable.
    let syncFraction: Double

    init(buffer: Buffer, revision: Int) {
        self.buffer = buffer
        self.revision = revision
        self.syncFraction = buffer.syncScroll
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        Self.makeWebView(coordinator: context.coordinator)
    }

    static func makeWebView(coordinator: Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = coordinator
        let script = """
        let lastSent = -1;
        window.addEventListener('scroll', () => {
          const value = window.scrollY / Math.max(1, document.documentElement.scrollHeight - innerHeight);
          if (Math.abs(value - lastSent) > 0.002) { lastSent = value; window.webkit.messageHandlers.previewScroll.postMessage({y: window.scrollY, fraction: value}); }
        }, {passive: true});
        """
        config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        config.userContentController.add(coordinator, contentWorld: .defaultClient, name: "previewScroll")
        web.underPageBackgroundColor = .textBackgroundColor
        web.setValue(false, forKey: "drawsBackground")
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        update(web, coordinator: context.coordinator)
    }

    func update(_ web: WKWebView, coordinator c: Coordinator) {
        if c.revision == revision, c.buffer === buffer {
            if buffer.viewMode == .split, abs(c.lastSync - syncFraction) > 0.002 {
                c.lastSync = syncFraction
                c.applyingSync = true
                web.evaluateJavaScript("window.scrollTo(0, \(syncFraction) * Math.max(0, document.documentElement.scrollHeight - innerHeight))", in: nil, in: .defaultClient) { _ in c.applyingSync = false }
            }
            return
        }
        c.revision = revision
        let switched = c.buffer !== buffer
        c.buffer = buffer
        let html = MarkdownHTML.page(buffer.text)
        let base = buffer.url?.deletingLastPathComponent()
        web.evaluateJavaScript("window.scrollY", in: nil, in: .defaultClient) { y in
            guard c.revision == revision, c.buffer === buffer else { return }
            c.pendingLoad = true
            c.restoreY = switched ? buffer.previewScroll : (try? y.get() as? Double) ?? buffer.previewScroll
            web.loadHTMLString(html, baseURL: base)
        }
    }

    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "previewScroll", contentWorld: .defaultClient)
        web.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastSync = 0.0
        var applyingSync = false
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let values = message.body as? [String: Double], let b = buffer else { return }
            b.previewScroll = max(0, values["y"] ?? 0)
            if !applyingSync, b.viewMode == .split {
                lastSync = min(1, max(0, values["fraction"] ?? 0))
                b.syncScroll = lastSync
            }
            b.workspace?.scheduleSave()
        }
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
