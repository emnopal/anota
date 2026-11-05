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
        case .error: .systemRed
        case .warning: .systemOrange
        case .info: .systemGreen
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
        buffer.highlightAll()  // colours are per layout manager
        let tc = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        lm.addTextContainer(tc)

        let tv = CodeTextView(frame: .zero, textContainer: tc)
        tv.configure()
        tv.delegate = context.coordinator
        tv.onFocus = onFocus
        tv.buffer = buffer

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = tv
        scroll.verticalRulerView = LineNumberRuler(textView: tv, scrollView: scroll) { [buffer] in buffer.lines }
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
            buffer.caretLine = buffer.lines.line(at: loc)
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
    weak var buffer: Buffer?

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
        if let b = buffer ?? Workspace.shared.active { Task { await Workspace.shared.format(b) } }
    }

    @objc private func formatSelection() {
        if let b = buffer ?? Workspace.shared.active { Task { await Workspace.shared.format(b, selection: true) } }
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(formatSelection) { return selectedRange().length > 0 }
        return super.validateMenuItem(item)
    }

    // MARK: VS Code-style line commands (wired to the Selection menu)

    /// Full lines touched by the selection; a selection ending at a line start doesn't include that line.
    private var selectedLines: NSRange {
        let s = string as NSString
        var sel = selectedRange()
        if sel.length > 0, sel.location + sel.length <= s.length,
           NSMaxRange(sel) > 0, s.character(at: NSMaxRange(sel) - 1) == 10 { sel.length -= 1 }
        return s.lineRange(for: sel)
    }

    /// Undoable replace through the text view, so undo, highlighting and dirty state all follow.
    private func edit(_ range: NSRange, _ text: String, select: NSRange) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        setSelectedRange(select)
        scrollRangeToVisible(select)
    }

    private func substring(_ r: NSRange) -> String { (string as NSString).substring(with: r) }

    @objc func toggleLineComment(_ sender: Any?) {
        guard let c = buffer?.language.lineComment else { NSSound.beep(); return }
        let r = selectedLines, old = substring(r)
        let new = LineEdits.toggleComment(old, prefix: c.prefix, suffix: c.suffix)
        edit(r, new, select: NSRange(location: r.location, length: (new as NSString).length - (new.hasSuffix("\n") ? 1 : 0)))
    }

    @objc func indentLines(_ sender: Any?) { reindent(outdent: false) }
    @objc func outdentLines(_ sender: Any?) { reindent(outdent: true) }

    private func reindent(outdent: Bool) {
        let r = selectedLines, new = LineEdits.indent(substring(r), outdent: outdent)
        edit(r, new, select: NSRange(location: r.location, length: (new as NSString).length - (new.hasSuffix("\n") ? 1 : 0)))
    }

    @objc func moveLinesUp(_ sender: Any?) { moveLines(up: true) }
    @objc func moveLinesDown(_ sender: Any?) { moveLines(up: false) }

    private func moveLines(up: Bool) {
        let s = string as NSString, block = selectedLines, sel = selectedRange()
        var blockText = substring(block)
        if up {
            guard block.location > 0 else { return }
            let prev = s.lineRange(for: NSRange(location: block.location - 1, length: 0))
            var prevText = substring(prev)
            if !blockText.hasSuffix("\n") { blockText += "\n"; prevText.removeLast() }  // block was the last line
            edit(NSUnionRange(prev, block), blockText + prevText,
                 select: NSRange(location: sel.location - prev.length, length: sel.length))
        } else {
            guard NSMaxRange(block) < s.length else { return }
            let next = s.lineRange(for: NSRange(location: NSMaxRange(block), length: 0))
            var nextText = substring(next)
            if !nextText.hasSuffix("\n") { nextText += "\n"; blockText.removeLast() }  // next is the last line
            edit(NSUnionRange(block, next), nextText + blockText,
                 select: NSRange(location: sel.location + (nextText as NSString).length, length: sel.length))
        }
    }

    @objc func copyLinesUp(_ sender: Any?) { copyLines(up: true) }
    @objc func copyLinesDown(_ sender: Any?) { copyLines(up: false) }

    private func copyLines(up: Bool) {
        let block = selectedLines, sel = selectedRange()
        var text = substring(block)
        if text.hasSuffix("\n") {
            edit(NSRange(location: block.location, length: 0), text,
                 select: up ? sel : NSRange(location: sel.location + block.length, length: sel.length))
        } else {  // last line without a newline: append "\n" + copy
            text = "\n" + text
            edit(NSRange(location: NSMaxRange(block), length: 0), text,
                 select: up ? sel : NSRange(location: sel.location + (text as NSString).length, length: sel.length))
        }
    }

    @objc func deleteLines(_ sender: Any?) {
        var r = selectedLines
        if !substring(r).hasSuffix("\n"), r.location > 0 { r = NSRange(location: r.location - 1, length: r.length + 1) }
        let s = string as NSString
        let caret = min(r.location, s.length - r.length)
        edit(r, "", select: NSRange(location: max(caret, 0), length: 0))
    }

    @objc func insertLineBelow(_ sender: Any?) {
        if let run = buffer?.onCommandReturn { run(); return }  // SQL box: ⌘↩ runs the query
        insertLine(above: false)
    }
    @objc func insertLineAbove(_ sender: Any?) { insertLine(above: true) }

    private func insertLine(above: Bool) {
        let s = string as NSString
        let line = s.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        let text = substring(line)
        let indent = String(text.prefix { $0 == " " || $0 == "\t" })
        let indentLen = (indent as NSString).length
        if above {
            edit(NSRange(location: line.location, length: 0), indent + "\n",
                 select: NSRange(location: line.location + indentLen, length: 0))
        } else {
            let end = NSMaxRange(line) - (text.hasSuffix("\n") ? 1 : 0)
            edit(NSRange(location: end, length: 0), "\n" + indent, select: NSRange(location: end + 1 + indentLen, length: 0))
        }
    }

    /// ⌘L: select the current line; again extends to the next line.
    @objc func expandLineSelection(_ sender: Any?) {
        let s = string as NSString
        var r = s.lineRange(for: selectedRange())
        if r == selectedRange(), NSMaxRange(r) < s.length { r = NSUnionRange(r, s.lineRange(for: NSRange(location: NSMaxRange(r), length: 0))) }
        setSelectedRange(r)
        scrollRangeToVisible(r)
    }

    /// ⌘D: select the word at the caret; if something is selected, jump to its next occurrence (wrapping).
    /// ponytail: single selection; VS Code adds a cursor per occurrence. Needs multi-cursor support.
    @objc func selectNextOccurrence(_ sender: Any?) {
        let s = string as NSString, sel = selectedRange()
        if sel.length == 0 {
            let word = selectionRange(forProposedRange: sel, granularity: .selectByWord)
            if word.length > 0 { setSelectedRange(word) }
            return
        }
        let needle = s.substring(with: sel)
        var found = s.range(of: needle, range: NSRange(location: NSMaxRange(sel), length: s.length - NSMaxRange(sel)))
        if found.location == NSNotFound { found = s.range(of: needle, range: NSRange(location: 0, length: sel.location)) }
        guard found.location != NSNotFound else { NSSound.beep(); return }
        setSelectedRange(found)
        scrollRangeToVisible(found)
        showFindIndicator(for: found)
    }

    // MARK: Auto-closing pairs and indentation (logic in AnotaCore.AutoPair)

    private func apply(_ e: AutoPair.Edit) {
        if e.text.isEmpty && e.range.length == 0 { setSelectedRange(e.selection); return }  // step over a closer
        edit(e.range, e.text, select: e.selection)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let s = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        if !hasMarkedText(), s.count == 1, let c = s.first, let lang = buffer?.language,
           replacementRange.location == NSNotFound || replacementRange == selectedRange(),
           let e = AutoPair.type(c, in: self.string as NSString, selection: selectedRange(), language: lang) {
            apply(e)
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        if let lang = buffer?.language, let e = AutoPair.backspace(in: string as NSString, selection: selectedRange(), language: lang) {
            apply(e)
            return
        }
        super.deleteBackward(sender)
    }

    /// Return keeps the indent, adds a level after `{ [ (`, and puts a closer that follows on its own line.
    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText(), let lang = buffer?.language else { super.insertNewline(sender); return }
        apply(AutoPair.newline(in: string as NSString, selection: selectedRange(), language: lang))
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
    private let lines: () -> LineIndex

    init(textView: NSTextView, scrollView: NSScrollView, lines: @escaping () -> LineIndex) {
        self.textView = textView
        self.lines = lines
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
        let digits = max(3, String(lines().lineCount).count)
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
        let index = lines()
        let caretLine = index.line(at: tv.selectedRange().location)
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

        var line = index.line(at: chars.location)
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
