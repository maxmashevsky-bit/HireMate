import AppKit
import SwiftUI

@MainActor
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    @Binding var hasMultipleSelections: Bool
    var fontSize: Double
    var isPresented: Bool
    var onLimitExceeded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NoteScrollView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let editor = NSTextView(frame: .zero)
        editor.isRichText = false; editor.importsGraphics = false; editor.allowsUndo = true
        editor.isEditable = isPresented; editor.isSelectable = isPresented
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 6, height: 6)
        editor.textColor = .labelColor; editor.backgroundColor = .textBackgroundColor
        editor.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        editor.string = text
        let length = text.utf16.count
        let valid = selection.location >= 0 && selection.length >= 0 && selection.location <= length && selection.length <= length - selection.location
        editor.setSelectedRange(valid ? selection : NSRange(location: 0, length: 0))
        editor.delegate = context.coordinator
        scroll.documentView = editor
        scroll.isHidden = !isPresented
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self; coordinator.updating = true
        defer { coordinator.updating = false }
        let wasEditable = editor.isEditable
        editor.isEditable = isPresented; editor.isSelectable = isPresented
        scroll.isHidden = !isPresented
        if !isPresented, editor.window?.firstResponder === editor { editor.window?.makeFirstResponder(nil) }
        editor.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let changed = !editor.string.utf8.elementsEqual(text.utf8)
        if changed {
            let whole = NSRange(location: 0, length: editor.string.utf16.count)
            editor.breakUndoCoalescing()
            editor.insertText(text, replacementRange: whole)
            editor.breakUndoCoalescing()
        }
        let length = editor.string.utf16.count
        let valid = selection.location >= 0 && selection.length >= 0 && selection.location <= length && selection.length <= length - selection.location
        let range = valid ? selection : NSRange(location: 0, length: 0)
        if editor.selectedRange() != range { editor.setSelectedRange(range) }
        if isPresented && (changed || !wasEditable) { editor.window?.makeFirstResponder(editor); editor.scrollRangeToVisible(range) }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextEditor
        var updating = false
        private let noteUndoManager = UndoManager()
        init(_ parent: MarkdownTextEditor) {
            self.parent = parent
            super.init()
            noteUndoManager.levelsOfUndo = 30
        }
        func undoManager(for view: NSTextView) -> UndoManager? { noteUndoManager }
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard !updating else { return true }
            guard let range = Range(affectedCharRange, in: textView.string) else { return false }
            let bytes = textView.string.utf8.count - textView.string[range].utf8.count + (replacementString?.utf8.count ?? 0)
            guard bytes <= 1_048_576 else { parent.onLimitExceeded(); return false }
            return true
        }
        func textDidChange(_ notification: Notification) {
            guard !updating, let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            parent.selection = editor.selectedRange()
            parent.hasMultipleSelections = editor.selectedRanges.count > 1
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updating, let editor = notification.object as? NSTextView else { return }
            parent.selection = editor.selectedRange()
            parent.hasMultipleSelections = editor.selectedRanges.count > 1
        }
    }
    private final class NoteScrollView: NSScrollView {
        override func layout() {
            super.layout()
            guard let editor = documentView as? NSTextView else { return }
            editor.minSize = NSSize(width: 0, height: contentSize.height)
            let size = NSSize(width: contentSize.width, height: max(contentSize.height, editor.frame.height))
            if editor.frame.size != size { editor.setFrameSize(size) }
        }
    }
}
