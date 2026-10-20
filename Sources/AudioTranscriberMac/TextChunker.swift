/// Splits text into model-context-sized chunks, preferring to break at the
/// last sentence boundary before the limit so a chunk doesn't end
/// mid-sentence. Shared by ReportGenerator (map-reduce summarization) and
/// TextCleanupService (map-only cleanup), which both bound their local-LLM
/// calls the same way.
enum TextChunker {
    static func chunk(_ text: String, maxCharacters: Int) -> [String] {
        guard text.count > maxCharacters else { return [text] }
        var chunks: [String] = []
        var remaining = Substring(text)
        while !remaining.isEmpty {
            if remaining.count <= maxCharacters {
                chunks.append(String(remaining))
                break
            }
            let limitIndex = remaining.index(remaining.startIndex, offsetBy: maxCharacters)
            let breakIndex = remaining[remaining.startIndex..<limitIndex]
                .lastIndex(where: { ".!?".contains($0) })
                .map { remaining.index(after: $0) } ?? limitIndex
            chunks.append(String(remaining[remaining.startIndex..<breakIndex]))
            remaining = remaining[breakIndex...]
        }
        return chunks
    }
}
