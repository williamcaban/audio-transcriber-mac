enum TranslationServiceError: Error {
    case translationFailed(String)
}

/// Translates text to a target language using the shared local LLM (see
/// LocalLLM.swift). Chosen over Apple's on-device Translation framework,
/// which in real testing required separately downloading per-language
/// packs with no reliable in-app way to trigger/confirm that download, and
/// flatly rejects translating a language into one of its own regional
/// variants (TranslationError.unsupportedLanguagePairing, e.g. English to
/// English (UK)). The local LLM is already downloaded for Report &
/// Summary/Cleanup, so this adds no new download, its target-language list
/// is the same plain Qwen3Languages names used elsewhere (no region
/// variants to accidentally collide with), and "translate into the same
/// language" is just a no-op prompt rather than a hard error.
enum TranslationService {
    // Same budget as ReportGenerator/TextCleanupService, well short of the
    // local model's much larger context window to leave headroom for less
    // token-efficient scripts plus the instructions/prompt wrapper and the
    // response itself.
    private static let maxChunkCharacters = 20000

    /// Translates the full text, chunking (map-only, not map-reduce -- each
    /// chunk is translated independently and the results concatenated back
    /// in order) for text too long for one model call.
    static func translate(
        _ text: String,
        to language: String,
        onStatusUpdate: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        do {
            _ = try await LocalLLM.loadContainer { progress, message in
                onStatusUpdate?(progress > 0 ? "\(message) (\(Int(progress * 100))%)" : message)
            }

            let chunks = TextChunker.chunk(text, maxCharacters: maxChunkCharacters)
            guard chunks.count > 1 else {
                onStatusUpdate?("Translating...")
                return try await translateChunk(text, to: language)
            }

            var translated: [String] = []
            for (index, chunk) in chunks.enumerated() {
                try Task.checkCancellation()
                onStatusUpdate?("Translating part \(index + 1) of \(chunks.count)...")
                translated.append(try await translateChunk(chunk, to: language))
            }
            // Each chunk is a contiguous slice of the original text, so
            // trim and rejoin with a single space rather than a paragraph
            // break -- the model may or may not preserve a chunk's
            // boundary whitespace verbatim.
            return translated
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: " ")
        } catch let error as CancellationError {
            throw error
        } catch {
            throw TranslationServiceError.translationFailed("\(error)")
        }
    }

    private static func translateChunk(_ chunk: String, to language: String) async throws -> String {
        try await LocalLLM.respond(
            instructions: """
            You translate text into \(language), preserving the original \
            meaning, tone, and formatting (including any Markdown syntax) \
            exactly -- do not summarize, add, or remove content. If the \
            text is already in \(language), return it unchanged. Respond \
            with only the translated text, no commentary.
            """,
            prompt: chunk
        )
    }
}
