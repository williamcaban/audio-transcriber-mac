import AppKit

/// Converts the local LLM's Markdown output (Report & Summary, Translation)
/// into real formatted text, for display and for Word export.
///
/// `AttributedString(markdown:)` parses block structure (headings, lists,
/// code blocks, block quotes) as `presentationIntent` metadata on an
/// otherwise *flat* string -- confirmed by direct experimentation, not
/// guessed from documentation: parsing "# Hi\n\n- one\n- two" produces the
/// plain characters "HionTwo" with no separators at all between blocks.
/// Reconstructing real paragraph breaks and list bullets means grouping
/// runs by each block's own unique `identity` and inserting them back in
/// ourselves.
enum MarkdownRenderer {
    // Computed, not a stored `static let` -- NSFont isn't Sendable, and a
    // stored static property of a non-Sendable type is flagged as
    // concurrency-unsafe shared global state under strict concurrency.
    private static var bodyFont: NSFont { .systemFont(ofSize: NSFont.systemFontSize) }

    static func render(_ markdown: String) -> NSAttributedString {
        guard let parsed = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .full)) else {
            return NSAttributedString(string: markdown, attributes: [.font: bodyFont])
        }

        let result = NSMutableAttributedString()
        var previousBlockID: Int?
        var previousListID: Int?

        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            guard !text.isEmpty else { continue }

            let components = run.presentationIntent?.components ?? []
            let blockID = components.first?.identity
            let listID = components.first(where: isListContainer)?.identity

            if let previousBlockID, blockID != previousBlockID {
                // Consecutive items in the same list get a single line
                // break; anything else (a new paragraph, heading, or the
                // first item after/before a list) gets a blank line.
                let sameList = listID != nil && listID == previousListID
                result.append(NSAttributedString(string: sameList ? "\n" : "\n\n"))
            }
            if blockID != previousBlockID {
                result.append(listPrefix(for: components))
            }
            previousBlockID = blockID
            previousListID = listID

            result.append(styledRun(text, components: components, run: run))
        }

        return result
    }

    private static func isListContainer(_ component: PresentationIntent.IntentType) -> Bool {
        switch component.kind {
        case .orderedList, .unorderedList: true
        default: false
        }
    }

    private static func headingLevel(_ components: [PresentationIntent.IntentType]) -> Int? {
        for component in components {
            if case .header(let level) = component.kind { return level }
        }
        return nil
    }

    private static func listOrdinal(_ components: [PresentationIntent.IntentType]) -> (ordinal: Int, ordered: Bool)? {
        var ordinal: Int?
        var ordered = false
        for component in components {
            switch component.kind {
            case .listItem(let value): ordinal = value
            case .orderedList: ordered = true
            default: break
            }
        }
        guard let ordinal else { return nil }
        return (ordinal, ordered)
    }

    private static func isCodeBlock(_ components: [PresentationIntent.IntentType]) -> Bool {
        for component in components {
            if case .codeBlock = component.kind { return true }
        }
        return false
    }

    private static func isBlockQuote(_ components: [PresentationIntent.IntentType]) -> Bool {
        for component in components {
            if case .blockQuote = component.kind { return true }
        }
        return false
    }

    private static func listPrefix(for components: [PresentationIntent.IntentType]) -> NSAttributedString {
        guard let (ordinal, ordered) = listOrdinal(components) else { return NSAttributedString() }
        let prefix = ordered ? "\(ordinal). " : "\u{2022} "
        return NSAttributedString(string: prefix, attributes: [.font: bodyFont])
    }

    private static func styledRun(
        _ text: String,
        components: [PresentationIntent.IntentType],
        run: AttributedString.Runs.Run
    ) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [:]
        var font = bodyFont

        if let level = headingLevel(components) {
            // Diminishing size by level, always bold; clamped so a deeply
            // nested heading (level 6) doesn't shrink below body size.
            let size = bodyFont.pointSize + max(0, 8 - CGFloat(level) * 2)
            font = NSFontManager.shared.convert(.systemFont(ofSize: size), toHaveTrait: .boldFontMask)
        } else if isCodeBlock(components) {
            font = .monospacedSystemFont(ofSize: bodyFont.pointSize, weight: .regular)
        } else if isBlockQuote(components) {
            font = NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)
            attributes[.foregroundColor] = NSColor.secondaryLabelColor
        }

        if let inline = run.inlinePresentationIntent {
            if inline.contains(.stronglyEmphasized) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            if inline.contains(.emphasized) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
            if inline.contains(.code) {
                font = .monospacedSystemFont(ofSize: bodyFont.pointSize, weight: .regular)
            }
            if inline.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
        }

        if let link = run.link {
            attributes[.link] = link
        }

        // Indent nested content (list items, block quotes, code) so it
        // reads as structured rather than flush against the body margin.
        if listOrdinal(components) != nil || isBlockQuote(components) || isCodeBlock(components) {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.headIndent = 20
            paragraphStyle.firstLineHeadIndent = listOrdinal(components) != nil ? 4 : 20
            attributes[.paragraphStyle] = paragraphStyle
        }

        attributes[.font] = font
        return NSAttributedString(string: text, attributes: attributes)
    }
}
