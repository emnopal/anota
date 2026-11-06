import AppKit
import AnotaCore
import WebKit

extension Workspace {
    func exportMarkdown(pdf: Bool) {
        guard let b = active, b.language == .markdown else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (b.name as NSString).deletingPathExtension + (pdf ? ".pdf" : ".html")
        guard let url = savePanelURL(panel) else { return }
        let html = MarkdownHTML.page(b.text)
        if !pdf {
            do { try html.write(to: url, atomically: true, encoding: .utf8); flash("Exported HTML") }
            catch { alert("Can't export HTML", error) }
        } else {
            let exporter = MarkdownExporter()
            markdownExporter = exporter
            exporter.export(html, base: b.url?.deletingLastPathComponent(), to: url) { [weak self] error in
                if let error { self?.alert("Can't export PDF", error) } else { self?.flash("Exported PDF") }
                self?.markdownExporter = nil
            }
        }
    }
}

final class MarkdownExporter: NSObject, WKNavigationDelegate {
    private var web: WKWebView?
    private var destination: URL?
    private var completion: ((Error?) -> Void)?
    func export(_ html: String, base: URL?, to url: URL, completion: @escaping (Error?) -> Void) {
        self.completion = completion; destination = url
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 1100), configuration: config)
        self.web = web; web.navigationDelegate = self
        web.loadHTMLString(html, baseURL: base)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.documentElement.scrollHeight", in: nil, in: .defaultClient) { [weak self] result in
            guard let self else { return }
            let configuration = WKPDFConfiguration()
            configuration.rect = NSRect(x: 0, y: 0, width: 800, height: max(1100, (try? result.get() as? Double) ?? 1100))
            webView.createPDF(configuration: configuration) { [weak self] result in
                guard let self, let destination = self.destination else { return }
                do { try result.get().write(to: destination, options: .atomic); self.completion?(nil) }
                catch { self.completion?(error) }
                self.web = nil
            }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { completion?(error); web = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { completion?(error); web = nil }
}
