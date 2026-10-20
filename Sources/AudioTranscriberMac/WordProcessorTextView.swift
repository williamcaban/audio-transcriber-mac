import AppKit
import SwiftUI

/// An editable multi-line text view backed by a real NSTextView -- the
/// word-processor-style control used to display and edit the transcript,
/// generated report, and translation text. Editable rather than read-only
/// so a user can fix genuine transcription mistakes the same way they would
/// in Pages or Word, or trigger the AI cleanup pass and continue editing
/// its result.
struct WordProcessorTextView: NSViewRepresentable {
    @Binding var text: String
    /// Whether `text` is Markdown (Report & Summary, Translation) that
    /// should be rendered as real formatted text rather than shown as raw
    /// source (the Transcript tab's ASR output isn't Markdown and should
    /// never be reinterpreted as such).
    var isMarkdown: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = isMarkdown
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
        render(text, into: textView)

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
        // For Markdown content, `text` holds the raw source (e.g.
        // "# Heading"), never what's actually on screen (the rendered
        // "Heading") -- comparing them directly would re-render on every
        // single SwiftUI update pass, destroying the user's live edits.
        // Only re-render when `text` is genuinely new content from outside
        // (Generate/Translate/Cleanup finishing), tracked via the
        // coordinator's record of what it last rendered.
        guard text != context.coordinator.lastRenderedText else { return }
        context.coordinator.lastRenderedText = text
        render(text, into: textView)
    }

    private func render(_ text: String, into textView: NSTextView) {
        if isMarkdown {
            textView.textStorage?.setAttributedString(MarkdownRenderer.render(text))
        } else if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        var lastRenderedText: String

        init(text: Binding<String>) {
            self.text = text
            self.lastRenderedText = text.wrappedValue
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            lastRenderedText = textView.string
        }
    }
}
