import AppKit
import AnotaCore
import SwiftUI

enum Theme {
    static var font: NSFont { NSFontManager.shared.font(withFamily: EditorSettings.shared.fontName, traits: [], weight: 5, size: min(36, max(9, EditorSettings.shared.fontSize))) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular) }
    static var gutterFont: NSFont { NSFont.monospacedDigitSystemFont(ofSize: max(10, font.pointSize - 2), weight: .regular) }
    static let lineSpacing: CGFloat = 3

    static var baseAttributes: [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = lineSpacing
        p.tabStops = []
        p.defaultTabInterval = (" " as NSString).size(withAttributes: [.font: font]).width * CGFloat(EditorSettings.shared.tabWidth)
        return [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: p]
    }

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
    var syncFraction: Double = 0
    var isActive: () -> Bool = { true }
    let onFocus: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(buffer: buffer) }

    func makeNSView(context: Context) -> NSScrollView { makeEditor(coordinator: context.coordinator) }

    func makeEditor(coordinator: Coordinator) -> NSScrollView {
        let lm = NSLayoutManager()
        lm.allowsNonContiguousLayout = true
        buffer.storage.addLayoutManager(lm)
        buffer.highlightAll()  // colours are per layout manager
        let tc = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        lm.addTextContainer(tc)

        let tv = CodeTextView(frame: .zero, textContainer: tc)
        tv.configure()
        tv.applySettings()
        tv.delegate = coordinator
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
        coordinator.applyWrap(wrap, tv, scroll)

        let sel = clamp(reveal ?? buffer.selection)
        tv.setSelectedRange(sel)
        DispatchQueue.main.async {
            guard tv.buffer === buffer, coordinator.buffer === buffer, isActive(), tv.window != nil else { return }
            tv.restoreScroll()
            if reveal != nil { tv.scrollRangeToVisible(sel) }
            tv.window?.makeFirstResponder(tv)
            if reveal != nil { buffer.reveal = nil }
        }
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(tv, selector: #selector(CodeTextView.scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) { updateEditor(scroll, coordinator: context.coordinator) }

    func updateEditor(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let tv = scroll.documentView as? CodeTextView else { return }
        tv.onFocus = onFocus
        if coordinator.buffer !== buffer, let lm = tv.layoutManager {
            lm.textStorage?.removeLayoutManager(lm)
            buffer.storage.addLayoutManager(lm)
            coordinator.buffer = buffer
            tv.buffer = buffer
            scroll.verticalRulerView = LineNumberRuler(textView: tv, scrollView: scroll) { [buffer] in buffer.lines }
            buffer.highlightAll()
            tv.setSelectedRange(clamp(buffer.selection))
        }
        tv.applySettings()
        coordinator.applyWrap(wrap, tv, scroll)
        if buffer.viewMode == .split, abs(buffer.syncScroll - coordinator.lastSync) > 0.001 {
            coordinator.lastSync = buffer.syncScroll
            tv.restoreScroll(fraction: buffer.syncScroll)
        }
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
        var buffer: Buffer
        private var wrapApplied: Bool?
        var lastSync = 0.0

        init(buffer: Buffer) { self.buffer = buffer }

        func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            buffer.workspace?.languageServer?.completionWords ?? words
        }

        // Per-buffer undo stack instead of the window's shared one.
        func undoManager(for view: NSTextView) -> UndoManager? { buffer.undoManager }

        func textViewDidChangeSelection(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            let loc = tv.selectedRange().location
            let s = tv.string as NSString
            buffer.selection = tv.selectedRange()
            (tv as? CodeTextView)?.highlightBrackets()
            buffer.workspace?.scheduleSave()
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
    private var settingsSignature = ""
    private var restoringScroll = false
    private var bracketRanges: [NSRange] = []
    // TextKit 1 discards all but one empty range; retain insertion points between keystrokes.
    private var multipleRanges: [NSValue]?
    private var settingRanges = false
    override var selectedRanges: [NSValue] {
        get { multipleRanges ?? super.selectedRanges }
        set { setSelectedRanges(newValue, affinity: .downstream, stillSelecting: false) }
    }
    override func setSelectedRange(_ charRange: NSRange) {
        if !settingRanges { multipleRanges = nil }
        super.setSelectedRange(charRange)
    }
    private var ws: Workspace { buffer?.workspace ?? Workspace.shared }
    private var indentUnit: String { buffer?.indentUnit ?? EditorSettings.shared.unit }

    func applySettings() {
        let settings = EditorSettings.shared
        let signature = "\(settings.fontName)/\(settings.fontSize)/\(settings.tabWidth)/\(settings.theme)"
        guard signature != settingsSignature else { return }
        settingsSignature = signature
        font = Theme.font
        typingAttributes = Theme.baseAttributes
        textStorage?.addAttributes(Theme.baseAttributes, range: NSRange(location: 0, length: textStorage?.length ?? 0))
        appearance = settings.theme == "System" ? nil : NSAppearance(named: ["Dark", "Midnight"].contains(settings.theme) ? .darkAqua : .aqua)
        backgroundColor = settings.theme == "Solarized" ? NSColor(red: 0.99, green: 0.96, blue: 0.89, alpha: 1)
            : settings.theme == "Midnight" ? NSColor(red: 0.07, green: 0.09, blue: 0.15, alpha: 1) : .textBackgroundColor
        (enclosingScrollView?.verticalRulerView as? LineNumberRuler)?.textChanged()
    }

    @objc func scrolled() {
        guard !restoringScroll, let scroll = enclosingScrollView, let buffer else { return }
        let maxY = max(1, bounds.height - scroll.contentView.bounds.height)
        buffer.scrollFraction = min(1, max(0, scroll.contentView.bounds.minY / maxY))
        if window?.firstResponder === self { buffer.syncScroll = buffer.scrollFraction }
        ws.scheduleSave()
    }

    func restoreScroll(fraction: Double? = nil) {
        guard let scroll = enclosingScrollView, let buffer else { return }
        restoringScroll = true
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: max(0, bounds.height - scroll.contentView.bounds.height) * (fraction ?? buffer.scrollFraction)))
        scroll.reflectScrolledClipView(scroll.contentView)
        restoringScroll = false
    }

    func highlightBrackets() {
        guard let lm = layoutManager else { return }
        for r in bracketRanges where NSMaxRange(r) <= (string as NSString).length { lm.removeTemporaryAttribute(.underlineStyle, forCharacterRange: r) }
        bracketRanges = selectedRange().length == 0 ? BracketMatch.ranges(in: string as NSString, caret: selectedRange().location) : []
        for r in bracketRanges { lm.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue, forCharacterRange: r) }
    }


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
        // Pane drop targets handle file URLs; NSTextView otherwise inserts their paths as text.
        unregisterDraggedTypes()
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
        return ws.find.barFrame.contains(p)
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
        wrap.state = ws.wrap ? .on : .off
        menu.insertItem(wrap, at: 0)
        menu.insertItem(.separator(), at: 0)
        let sel = NSMenuItem(title: "Format Selection", action: #selector(formatSelection), keyEquivalent: "")
        sel.isEnabled = selectedRange().length > 0
        menu.insertItem(sel, at: 0)
        menu.insertItem(NSMenuItem(title: "Format Document", action: #selector(formatDocument), keyEquivalent: ""), at: 0)
        return menu
    }

    @objc private func toggleWrap() { ws.wrap.toggle() }

    @objc private func formatDocument() {
        if let b = buffer ?? ws.active { Task { await ws.format(b) } }
    }

    @objc private func formatSelection() {
        if let b = buffer ?? ws.active { Task { await ws.format(b, selection: true) } }
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
        let r = selectedLines, new = LineEdits.indent(substring(r), unit: indentUnit, outdent: outdent)
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
    /// Adds a native selection at the next occurrence, keeping existing selections.
    @objc func selectNextOccurrence(_ sender: Any?) {
        let s = string as NSString, sel = selectedRanges.last?.rangeValue ?? selectedRange()
        if sel.length == 0 {
            let word = selectionRange(forProposedRange: sel, granularity: .selectByWord)
            if word.length > 0 { setSelectedRange(word) }
            return
        }
        let needle = s.substring(with: sel)
        var found = s.range(of: needle, range: NSRange(location: NSMaxRange(sel), length: s.length - NSMaxRange(sel)))
        if found.location == NSNotFound { found = s.range(of: needle, range: NSRange(location: 0, length: sel.location)) }
        let existing = selectedRanges.map(\.rangeValue)
        if existing.contains(found) { NSSound.beep(); return }
        guard found.location != NSNotFound else { NSSound.beep(); return }
        var ranges = selectedRanges.map(\.rangeValue)
        if !ranges.contains(found) { ranges.append(found) }
        setSelectedRanges(ranges.sorted { $0.location < $1.location }.map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false)
        scrollRangeToVisible(found)
        showFindIndicator(for: found)
    }

    private var showingCompletions = false
    override func complete(_ sender: Any?) {
        if showingCompletions { super.complete(sender); return }
        guard let buffer else { return }
        ws.languageServer?.complete(buffer, offset: selectedRange().location) { [weak self] in
            guard let self else { return }
            self.showingCompletions = true
            self.complete(sender)
            self.showingCompletions = false
        }
    }

    @objc func addCursorAbove(_ sender: Any?) { addCursor(-1) }
    @objc func addCursorBelow(_ sender: Any?) { addCursor(1) }
    private func addCursor(_ step: Int) {
        guard let buffer else { return }
        var ranges = selectedRanges.map(\.rangeValue)
        guard let edge = step < 0 ? ranges.first : ranges.last else { return }
        let line = buffer.lines.line(at: edge.location), target = line + step
        guard target >= 1, target <= buffer.lines.lineCount else { return }
        let column = edge.location - buffer.lines.start(ofLine: line)
        let start = buffer.lines.start(ofLine: target)
        let end = target < buffer.lines.lineCount ? buffer.lines.start(ofLine: target + 1) - 1 : (string as NSString).length
        let range = NSRange(location: min(end, start + column), length: 0)
        guard !ranges.contains(range) else { return }
        ranges.append(range)
        setSelectedRanges(ranges.sorted { $0.location < $1.location }.map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false)
    }

    @objc func markdownBold(_ sender: Any?) { wrapMarkdown("**") }
    @objc func markdownItalic(_ sender: Any?) { wrapMarkdown("*") }
    private func wrapMarkdown(_ marker: String) {
        guard buffer?.language == .markdown else { return }
        let r = selectedRange(), inner = substring(r)
        edit(r, marker + inner + marker, select: NSRange(location: r.location + marker.count, length: r.length))
    }

    override func insertTab(_ sender: Any?) {
        if selectedRange().length > 0 { reindent(outdent: false) }
        else { insertText(indentUnit, replacementRange: NSRange(location: NSNotFound, length: 0)) }
    }
    override func insertBacktab(_ sender: Any?) { reindent(outdent: true) }

    // MARK: Auto-closing pairs and indentation (logic in AnotaCore.AutoPair)

    private func apply(_ e: AutoPair.Edit) {
        if e.text.isEmpty && e.range.length == 0 { setSelectedRange(e.selection); return }  // step over a closer
        edit(e.range, e.text, select: e.selection)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let s = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        if selectedRanges.count > 1, !hasMarkedText(), replacementRange.location == NSNotFound {
            replaceSelections(with: s)
            return
        }
        if selectedRanges.count == 1, !hasMarkedText(), s.count == 1, let c = s.first, let lang = buffer?.language,
           replacementRange.location == NSNotFound || replacementRange == selectedRange(),
           let e = AutoPair.type(c, in: self.string as NSString, selection: selectedRange(), language: lang, indentUnit: indentUnit) {
            apply(e)
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        if selectedRanges.count > 1, !hasMarkedText() {
            let ns = string as NSString
            let ranges = selectedRanges.map(\.rangeValue).map { r in
                r.length > 0 || r.location == 0 ? r : ns.rangeOfComposedCharacterSequence(at: r.location - 1)
            }
            replaceSelections(with: "", ranges: ranges)
            return
        }
        if selectedRanges.count == 1, let lang = buffer?.language, let e = AutoPair.backspace(in: string as NSString, selection: selectedRange(), language: lang) {
            apply(e)
            return
        }
        super.deleteBackward(sender)
    }

    override func deleteForward(_ sender: Any?) {
        if selectedRanges.count > 1, !hasMarkedText() {
            let ns = string as NSString
            replaceSelections(with: "", ranges: selectedRanges.map(\.rangeValue).map { r in
                r.length > 0 || r.location >= ns.length ? r : ns.rangeOfComposedCharacterSequence(at: r.location)
            })
            return
        }
        super.deleteForward(sender)
    }

    private func replaceSelections(with replacement: String, ranges: [NSRange]? = nil) {
        let ranges = (ranges ?? selectedRanges.map(\.rangeValue)).sorted { $0.location < $1.location }
        var edits: [NSRange] = []
        for r in ranges {
            if let last = edits.last, NSMaxRange(last) > r.location {
                edits[edits.count - 1] = NSUnionRange(last, r)
            } else if edits.last != r { edits.append(r) }
        }
        guard shouldChangeText(inRanges: edits.map { NSValue(range: $0) }, replacementStrings: edits.map { _ in replacement }) else { return }
        textStorage?.beginEditing()
        for r in edits.reversed() { textStorage?.replaceCharacters(in: r, with: replacement) }
        textStorage?.endEditing()
        didChangeText()
        var delta = 0
        let newRanges = edits.map { r -> NSValue in
            let length = (replacement as NSString).length
            let caret = r.location + delta + length
            delta += length - r.length
            return NSValue(range: NSRange(location: caret, length: 0))
        }
        setSelectedRanges(newRanges, affinity: .downstream, stillSelecting: false)
    }

    /// Return keeps the indent, adds a level after `{ [ (`, and puts a closer that follows on its own line.
    override func insertNewline(_ sender: Any?) {
        if selectedRanges.count > 1, !hasMarkedText() { replaceSelections(with: "\n"); return }
        guard selectedRanges.count == 1, !hasMarkedText(), let lang = buffer?.language else { super.insertNewline(sender); return }
        if lang == .markdown {
            let r = selectedRange(), ns = string as NSString
            let line = ns.lineRange(for: NSRange(location: r.location, length: 0))
            let head = ns.substring(with: NSRange(location: line.location, length: r.location - line.location))
            if let continuation = MarkdownEditing.continuation(head) {
                if continuation.isEmpty {
                    edit(NSRange(location: line.location, length: NSMaxRange(r) - line.location), "", select: NSRange(location: line.location, length: 0))
                } else { edit(r, "\n" + continuation, select: NSRange(location: r.location + 1 + (continuation as NSString).length, length: 0)) }
                return
            }
        }
        apply(AutoPair.newline(in: string as NSString, selection: selectedRange(), language: lang, indentUnit: indentUnit))
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        settingRanges = true
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        multipleRanges = ranges.count > 1 ? ranges : nil
        settingRanges = false
        needsDisplay = true  // move the current-line highlight
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard window?.firstResponder === self, let window, let ranges = multipleRanges else { return }
        insertionPointColor.setFill()
        for range in ranges.map(\.rangeValue) where range.length == 0 && range != super.selectedRange() {
            let screen = firstRect(forCharacterRange: range, actualRange: nil)
            var caret = convert(window.convertFromScreen(screen), from: nil)
            caret.size.width = 1
            if caret.intersects(dirtyRect) { caret.fill() }
        }
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

    @objc func textChanged() {
        let digits = max(3, String(lines().lineCount).count)
        let width = CGFloat(digits) * ("8" as NSString).size(withAttributes: [.font: Theme.gutterFont]).width + 20
        if abs(ruleThickness - width) > 0.5 { ruleThickness = width }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        (textView?.backgroundColor ?? .textBackgroundColor).setFill()
        bounds.fill()
        NSColor.separatorColor.withAlphaComponent(0.4).setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()
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
                .foregroundColor: n == caretLine ? NSColor.labelColor : NSColor.secondaryLabelColor,
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
