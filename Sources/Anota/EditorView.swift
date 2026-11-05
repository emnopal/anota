import AppKit
import AnotaCore
import SwiftUI

enum Theme {
    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let gutterFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    static let lineSpacing: CGFloat = 3

    static let baseAttributes: [NSAttributedString.Key: Any] = {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = lineSpacing
        return [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: p]
    }()

    // System colors adapt to light/dark automatically.
    static func color(_ t: Token) -> NSColor {
        switch t {
        case .keyword: .systemPink
        case .string: .systemRed
        case .comment: .secondaryLabelColor
        case .number: .systemPurple
        case .type: .systemTeal
        case .key: .systemBlue
        case .heading: .systemOrange
        case .link: .linkColor
        case .emphasis: .systemIndigo
        case .function: .systemCyan
        }
    }
}

/// The editor: NSTextView (TextKit 1, so several views can share one NSTextStorage
/// and the line-number ruler can use NSLayoutManager).
struct EditorView: NSViewRepresentable {
    let buffer: Buffer
    let wrap: Bool
    let reveal: NSRange?
    let onFocus: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(buffer: buffer) }

    func makeNSView(context: Context) -> NSScrollView {
        let lm = NSLayoutManager()
        lm.allowsNonContiguousLayout = true
        buffer.storage.addLayoutManager(lm)
        let tc = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        lm.addTextContainer(tc)

        let tv = CodeTextView(frame: .zero, textContainer: tc)
        tv.configure()
        tv.delegate = context.coordinator
        tv.onFocus = onFocus

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = tv
        scroll.verticalRulerView = LineNumberRuler(textView: tv, scrollView: scroll)
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        context.coordinator.applyWrap(wrap, tv, scroll)

        let sel = clamp(reveal ?? buffer.selection)
        tv.setSelectedRange(sel)
        DispatchQueue.main.async {
            tv.scrollRangeToVisible(sel)
            tv.window?.makeFirstResponder(tv)
            Workspace.shared.find.highlight()
            if reveal != nil { buffer.reveal = nil }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? CodeTextView else { return }
        tv.onFocus = onFocus
        context.coordinator.applyWrap(wrap, tv, scroll)
        if let r = reveal {
            let r = clamp(r)
            tv.setSelectedRange(r)
            tv.scrollRangeToVisible(r)
            tv.showFindIndicator(for: r)
            DispatchQueue.main.async { buffer.reveal = nil }
        }
    }

    private func clamp(_ r: NSRange) -> NSRange {
        let len = buffer.storage.length
        let loc = min(r.location, len)
        return NSRange(location: loc, length: min(r.length, len - loc))
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        if let lm = (scroll.documentView as? NSTextView)?.layoutManager {
            lm.textStorage?.removeLayoutManager(lm)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let buffer: Buffer
        private var wrapApplied: Bool?

        init(buffer: Buffer) { self.buffer = buffer }

        // Per-buffer undo stack instead of the window's shared one.
        func undoManager(for view: NSTextView) -> UndoManager? { buffer.undoManager }

        func textViewDidChangeSelection(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            let loc = tv.selectedRange().location
            let s = tv.string as NSString
            buffer.selection = tv.selectedRange()
            buffer.caretLine = lineNumber(in: s, at: loc)
            buffer.caretColumn = loc - s.lineRange(for: NSRange(location: loc, length: 0)).location + 1
        }

        func applyWrap(_ wrap: Bool, _ tv: NSTextView, _ scroll: NSScrollView) {
            guard wrapApplied != wrap, let tc = tv.textContainer else { return }
            wrapApplied = wrap
            if wrap {
                tv.isHorizontallyResizable = false
                tc.widthTracksTextView = true
                tv.frame.size.width = scroll.contentSize.width
                scroll.hasHorizontalScroller = false
            } else {
                tc.widthTracksTextView = false
                tc.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                tv.isHorizontallyResizable = true
                scroll.hasHorizontalScroller = true
            }
        }
    }
}

final class CodeTextView: NSTextView {
    var onFocus: (() -> Void)?

    func configure() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        smartInsertDeleteEnabled = false
        font = Theme.font
        typingAttributes = Theme.baseAttributes
        textContainerInset = NSSize(width: 4, height: 8)
        isVerticallyResizable = true
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        autoresizingMask = [.width]
        drawsBackground = true
        backgroundColor = .textBackgroundColor
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus?() }
        return ok
    }

    // The find bar floats over the editor, but the text view's tracking area still sets the
    // I-beam there. Show the normal arrow while the pointer is over the bar.
    private func isOverFindBar(_ e: NSEvent) -> Bool {
        guard let content = window?.contentView else { return false }
        var p = content.convert(e.locationInWindow, from: nil)
        if !content.isFlipped { p.y = content.bounds.height - p.y }
        return Workspace.shared.find.barFrame.contains(p)
    }

    override func mouseMoved(with event: NSEvent) {
        if isOverFindBar(event) { NSCursor.arrow.set() } else { super.mouseMoved(with: event) }
    }

    override func cursorUpdate(with event: NSEvent) {
        if isOverFindBar(event) { NSCursor.arrow.set() } else { super.cursorUpdate(with: event) }
    }

    /// Right-click: the standard text menu plus formatting, mirroring the Edit menu.
    override func menu(for event: NSEvent) -> NSMenu? {
        onFocus?()  // right-click doesn't take focus; make this pane's buffer the active one
        let menu = super.menu(for: event) ?? NSMenu()
        menu.insertItem(.separator(), at: 0)
        let wrap = NSMenuItem(title: "Word Wrap", action: #selector(toggleWrap), keyEquivalent: "")
        wrap.state = Workspace.shared.wrap ? .on : .off
        menu.insertItem(wrap, at: 0)
        menu.insertItem(.separator(), at: 0)
        let sel = NSMenuItem(title: "Format Selection", action: #selector(formatSelection), keyEquivalent: "")
        sel.isEnabled = selectedRange().length > 0
        menu.insertItem(sel, at: 0)
        menu.insertItem(NSMenuItem(title: "Format Document", action: #selector(formatDocument), keyEquivalent: ""), at: 0)
        return menu
    }

    @objc private func toggleWrap() { Workspace.shared.wrap.toggle() }

    @objc private func formatDocument() {
        if let b = Workspace.shared.active { Task { await Workspace.shared.format(b) } }
    }

    @objc private func formatSelection() {
        if let b = Workspace.shared.active { Task { await Workspace.shared.format(b, selection: true) } }
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(formatSelection) { return selectedRange().length > 0 }
        return super.validateMenuItem(item)
    }

    /// Auto-indent: keep the current line's leading whitespace.
    override func insertNewline(_ sender: Any?) {
        let s = string as NSString
        let line = s.substring(with: s.lineRange(for: NSRange(location: selectedRange().location, length: 0)))
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        super.insertNewline(sender)
        if !indent.isEmpty { insertText(String(indent), replacementRange: selectedRange()) }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        needsDisplay = true  // move the current-line highlight
    }

    /// Current-line highlight.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lm = layoutManager, let tc = textContainer, selectedRange().length == 0 else { return }
        let s = string as NSString
        let loc = selectedRange().location
        var r: NSRect
        if loc >= s.length, s.length == 0 || s.character(at: s.length - 1) == 10 {
            r = lm.extraLineFragmentRect
        } else {
            let glyphs = lm.glyphRange(forCharacterRange: s.lineRange(for: NSRange(location: loc, length: 0)),
                                       actualCharacterRange: nil)
            r = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        }
        r.origin.x = 0
        r.size.width = bounds.width
        r.origin.y += textContainerOrigin.y
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        r.fill()
    }
}

final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        let nc = NotificationCenter.default
        if let storage = textView.textStorage {
            nc.addObserver(self, selector: #selector(textChanged), name: NSTextStorage.didProcessEditingNotification, object: storage)
        }
        nc.addObserver(self, selector: #selector(redraw), name: NSTextView.didChangeSelectionNotification, object: textView)
        scrollView.contentView.postsBoundsChangedNotifications = true
        nc.addObserver(self, selector: #selector(redraw), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        textChanged()
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func redraw() { needsDisplay = true }

    @objc private func textChanged() {
        let lines = textView.map { lineNumber(in: $0.string as NSString, at: ($0.string as NSString).length) } ?? 1
        let digits = max(3, String(lines).count)
        let width = CGFloat(digits) * ("8" as NSString).size(withAttributes: [.font: Theme.gutterFont]).width + 20
        if abs(ruleThickness - width) > 0.5 { ruleThickness = width }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let s = tv.string as NSString
        let chars = lm.characterRange(forGlyphRange: lm.glyphRange(forBoundingRect: tv.visibleRect, in: tc),
                                      actualGlyphRange: nil)
        let caretLine = lineNumber(in: s, at: tv.selectedRange().location)
        let originY = convert(NSPoint.zero, from: tv).y + tv.textContainerOrigin.y

        func draw(_ n: Int, _ frag: NSRect) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: Theme.gutterFont,
                .foregroundColor: n == caretLine ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor,
            ]
            let label = "\(n)" as NSString
            let size = label.size(withAttributes: attrs)
            let lineHeight = frag.height - Theme.lineSpacing
            label.draw(at: NSPoint(x: ruleThickness - size.width - 10,
                                   y: originY + frag.minY + (lineHeight - size.height) / 2),
                       withAttributes: attrs)
        }

        var line = lineNumber(in: s, at: chars.location)
        var i = chars.location
        while i < NSMaxRange(chars) {
            let lr = s.lineRange(for: NSRange(location: i, length: 0))
            draw(line, lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: lr.location), effectiveRange: nil))
            line += 1
            i = NSMaxRange(lr)
        }
        if NSMaxRange(chars) == s.length, !lm.extraLineFragmentRect.isEmpty {
            draw(line, lm.extraLineFragmentRect)
        }
    }
}
