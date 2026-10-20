import AppKit
import SwiftUI

/// A read-only, selectable multi-line text view backed by a real NSTextView.
///
/// The transcript display previously used `Text(...).textSelection(.enabled)`
/// inside a ScrollView. That combination has a reported reliability problem
/// on macOS: starting a text selection inside it can make the displayed
/// transcript disappear and not come back, even though the underlying
/// `transcript` string is untouched. Wrapping a plain NSTextView sidesteps
/// SwiftUI's Text-selection machinery entirely, which is also the more
/// native-feeling choice for a large block of copyable text.
struct SelectableTextView: NSViewRepresentable {
    var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
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
        let displayText = text.isEmpty ? placeholder : text
        if textView.string != displayText {
            textView.string = displayText
        }
        textView.textColor = text.isEmpty ? .secondaryLabelColor : .labelColor
    }
}
