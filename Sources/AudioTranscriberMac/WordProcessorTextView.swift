import AppKit
import SwiftUI

/// An editable, optionally spell-checked multi-line text view backed by a
/// real NSTextView -- the word-processor-style control used to display and
/// lightly correct the transcript (and, later, generated report/translation
/// text). Editable rather than read-only so a user can fix genuine
/// transcription mistakes the same way they would in Pages or Word.
///
/// Spell checking uses NSSpellChecker, which is a process-wide singleton:
/// `setLanguage` is called here (in `updateNSView`) rather than once at
/// setup, since the language can change per-tab/per-transcription and only
/// one such text view is ever on screen at a time in this app's TabView.
struct WordProcessorTextView: NSViewRepresentable {
    @Binding var text: String
    var isSpellCheckingEnabled: Bool
    var spellCheckLanguageCode: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude
        )
        textView.delegate = context.coordinator
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let textChanged = textView.string != text
        if textChanged {
            textView.string = text
        }

        let spellCheckingJustEnabled = isSpellCheckingEnabled && !context.coordinator.wasSpellCheckingEnabled
        textView.isContinuousSpellCheckingEnabled = isSpellCheckingEnabled
        textView.isGrammarCheckingEnabled = isSpellCheckingEnabled
        if isSpellCheckingEnabled, let code = spellCheckLanguageCode {
            NSSpellChecker.shared.setLanguage(code)
        }
        // Continuous spell checking only checks text as it's typed going
        // forward -- it does NOT retroactively scan text that's already
        // there (e.g. a freshly generated transcript), so toggling it on
        // would otherwise show no visible effect at all. Force an explicit
        // full-document check whenever checking just turned on, or whenever
        // new text arrives while it's already on.
        if isSpellCheckingEnabled, spellCheckingJustEnabled || textChanged {
            textView.checkTextInDocument(nil)
        }
        context.coordinator.wasSpellCheckingEnabled = isSpellCheckingEnabled
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        var wasSpellCheckingEnabled = false

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
