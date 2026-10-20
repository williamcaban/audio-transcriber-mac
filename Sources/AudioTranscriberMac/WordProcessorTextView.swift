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
        if textView.string != text {
            textView.string = text
        }
        textView.isContinuousSpellCheckingEnabled = isSpellCheckingEnabled
        textView.isGrammarCheckingEnabled = isSpellCheckingEnabled
        if isSpellCheckingEnabled, let code = spellCheckLanguageCode {
            NSSpellChecker.shared.setLanguage(code)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
