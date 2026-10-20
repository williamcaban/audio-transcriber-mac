enum TextCleanupError: Error {
    case cleanupFailed(String)
}

/// Cleans up transcript/report text using the shared local LLM (see
/// LocalLLM.swift): fixes spelling and grammar, and strips stray
/// foreign-script leakage -- Qwen3-ASR sometimes emits a few stray Chinese
/// characters/phrases in otherwise non-Chinese transcriptions, a known
/// multilingual-ASR artifact. Replaces the earlier NSSpellChecker-based
/// continuous "Spell Check" toggle, which only underlined issues rather than
/// fixing them and had no way to detect script leakage at all.
enum TextCleanupService {
    // Same budget as ReportGenerator, well short of the local model's much
    // larger context window to leave headroom for less token-efficient
    // scripts plus the instructions/prompt wrapper and the response itself.
    private static let maxChunkCharacters = 20000

    /// Cleans the full text, chunking (map-only, not map-reduce -- each
    /// chunk is corrected in place and the results concatenated back in
    /// order) for transcripts too long for one model call.
    static func cleanUp(
        _ text: String,
        onStatusUpdate: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        do {
            _ = try await LocalLLM.loadContainer { progress, message in
                onStatusUpdate?(progress > 0 ? "\(message) (\(Int(progress * 100))%)" : message)
            }

            let chunks = TextChunker.chunk(text, maxCharacters: maxChunkCharacters)
            guard chunks.count > 1 else {
                onStatusUpdate?("Cleaning up...")
                return try await cleanChunk(text)
            }

            var cleaned: [String] = []
            for (index, chunk) in chunks.enumerated() {
                try Task.checkCancellation()
                onStatusUpdate?("Cleaning up part \(index + 1) of \(chunks.count)...")
                cleaned.append(try await cleanChunk(chunk))
            }
            // Each chunk is a contiguous slice of the original text (unlike
            // ReportGenerator's independent per-chunk summaries), so trim
            // and rejoin with a single space rather than a paragraph break
            // -- the model may or may not preserve a chunk's boundary
            // whitespace verbatim.
            return cleaned
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: " ")
        } catch let error as CancellationError {
            throw error
        } catch {
            throw TextCleanupError.cleanupFailed("\(error)")
        }
    }

    private static func cleanChunk(_ chunk: String) async throws -> String {
        try await LocalLLM.respond(
            instructions: """
            You correct spelling and grammar in transcribed speech, \
            preserving the original meaning, wording, and language exactly \
            -- do not summarize, paraphrase, add, or remove content. Some \
            input may contain a few stray characters from an unrelated \
            script, mistakenly inserted by the speech recognizer (not \
            something the speaker actually said) -- remove those, but keep \
            any text genuinely meant to be in another language (e.g. a \
            quoted phrase or a bilingual speaker). Respond with only the \
            corrected text, no commentary, in the same language as the input.
            """,
            prompt: chunk
        )
    }
}
