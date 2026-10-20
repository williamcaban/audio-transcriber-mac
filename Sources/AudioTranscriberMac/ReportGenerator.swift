import FoundationModels

enum ReportGeneratorError: Error {
    case unavailable(String)
    case guardrailFlagged
    case contentTooLong
}

/// Generates a prose report and summary from a transcript using Apple's
/// on-device Foundation Models framework (macOS 26+, "Apple Intelligence").
///
/// Unlike speech-swift, there's no public source to read for this
/// framework, so its shape here is reconstructed from Apple's WWDC25
/// sessions/documentation rather than verified against real source --
/// the same risk class as AppleNativeTranscriber.swift, which needed one
/// real fix on its first CI compile. Expect the same here if a detail
/// (an enum case name, an initializer shape) turns out wrong.
enum ReportGenerator {
    // A real failure on real hardware revealed a hard ~4096-token context
    // window shared across instructions + prompt + the generated response
    // -- hit by an ordinary ~15-20 minute recording (7889 tokens), not just
    // extreme edge cases. There's no public tokenizer available here to
    // count exactly, so this uses a deliberately conservative
    // characters-per-chunk budget: well under a naive English-only
    // estimate, specifically to leave headroom for less token-efficient
    // scripts (CJK, Thai, etc, which can run closer to 1-2 characters per
    // token rather than English's ~4) plus the instructions/prompt wrapper
    // and the response itself.
    private static let maxChunkCharacters = 3000

    /// Checked at generation time rather than assumed, so unavailability
    /// (ineligible hardware, Apple Intelligence disabled, or the on-device
    /// model still downloading) is surfaced honestly instead of silently
    /// failing or producing a fake result.
    static func unavailabilityReason() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This Mac doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is turned off. Enable it in System Settings > Apple Intelligence & Siri."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence's on-device model isn't ready yet. Try again shortly."
        case .unavailable:
            return "Apple Intelligence isn't available on this Mac right now."
        }
    }

    /// Generates the final two-part summary + prose report. Transcripts
    /// that fit in one model call go straight through; longer ones are
    /// map-reduced -- summarized in bounded chunks, then those summaries
    /// combined (recursively, if even the combined summaries are still too
    /// large) before the final report is written. Same bounded-window-
    /// chunking shape already used for Qwen3-ASR's fixed audio window,
    /// just applied to this model's fixed context window instead.
    static func generateReport(
        from transcript: String,
        onStatusUpdate: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        if let reason = unavailabilityReason() {
            throw ReportGeneratorError.unavailable(reason)
        }

        let chunks = chunkText(transcript)
        guard chunks.count > 1 else {
            onStatusUpdate?("Writing report...")
            return try await writeReport(from: transcript)
        }

        var partialSummaries: [String] = []
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            onStatusUpdate?("Summarizing part \(index + 1) of \(chunks.count)...")
            partialSummaries.append(try await summarizeChunk(chunk))
        }

        onStatusUpdate?("Combining summaries...")
        let condensed = try await reduceToFit(partialSummaries)

        onStatusUpdate?("Writing report...")
        return try await writeReport(from: condensed)
    }

    private static func chunkText(_ text: String) -> [String] {
        guard text.count > maxChunkCharacters else { return [text] }
        var chunks: [String] = []
        var remaining = Substring(text)
        while !remaining.isEmpty {
            if remaining.count <= maxChunkCharacters {
                chunks.append(String(remaining))
                break
            }
            let limitIndex = remaining.index(remaining.startIndex, offsetBy: maxChunkCharacters)
            // Prefer breaking at the last sentence boundary before the
            // limit so a chunk doesn't end mid-sentence; falls back to the
            // raw character limit if no good boundary is found nearby.
            let breakIndex = remaining[remaining.startIndex..<limitIndex]
                .lastIndex(where: { ".!?".contains($0) })
                .map { remaining.index(after: $0) } ?? limitIndex
            chunks.append(String(remaining[remaining.startIndex..<breakIndex]))
            remaining = remaining[breakIndex...]
        }
        return chunks
    }

    /// Combines summaries into text small enough for one final report call,
    /// recursing (summaries-of-summaries) if even the combined text is
    /// still over budget -- needed for very long files with many chunks.
    private static func reduceToFit(_ summaries: [String]) async throws -> String {
        let joined = summaries.joined(separator: "\n\n")
        guard joined.count > maxChunkCharacters else { return joined }

        var nextLevel: [String] = []
        var batch: [String] = []
        var batchLength = 0
        for summary in summaries {
            if batchLength + summary.count > maxChunkCharacters, !batch.isEmpty {
                nextLevel.append(try await summarizeChunk(batch.joined(separator: "\n\n")))
                batch = []
                batchLength = 0
            }
            batch.append(summary)
            batchLength += summary.count
        }
        if !batch.isEmpty {
            nextLevel.append(try await summarizeChunk(batch.joined(separator: "\n\n")))
        }
        return try await reduceToFit(nextLevel)
    }

    private static func summarizeChunk(_ chunk: String) async throws -> String {
        let session = LanguageModelSession(
            instructions: """
            You extract the key points from part of a longer transcript or \
            set of summaries. Respond with concise bullet points only, in \
            the same language as the text. This is only one part of a \
            larger whole, so don't summarize it as if it were complete on \
            its own.
            """
        )
        return try await respond(session: session, prompt: "Content:\n\(chunk)")
    }

    private static func writeReport(from content: String) async throws -> String {
        let session = LanguageModelSession(
            instructions: """
            You write clear, well-organized prose reports and summaries from \
            spoken-word transcripts -- sermons, classes, movies, reviews, \
            meetings, and similar recordings. Always respond in the same \
            language as the source material.
            """
        )
        let prompt = """
        Write a report of the following in two parts, in this order:

        1. A descriptive summary highlighting the important points or ideas.
        2. A more detailed prose report capturing the important ideas, in \
        full paragraphs.

        Content:
        \(content)
        """
        return try await respond(session: session, prompt: prompt)
    }

    private static func respond(session: LanguageModelSession, prompt: String) async throws -> String {
        do {
            let response = try await session.respond(to: prompt)
            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            // Apple's on-device model has a built-in content-safety
            // guardrail that can flag the prompt or the response even for
            // ordinary transcripts (a real, observed case: a personal
            // family recording discussing relationships/religion). There's
            // no supported way to disable it -- surfaced as its own case so
            // the UI can give an honest, actionable message instead of a
            // raw technical error string.
            if case .guardrailViolation = error {
                throw ReportGeneratorError.guardrailFlagged
            }
            // Defense in depth: chunking above should keep every real call
            // well under the context limit, but if a language's actual
            // tokenization turns out denser than our character-based
            // estimate assumed, surface it cleanly rather than crash.
            if case .exceededContextWindowSize = error {
                throw ReportGeneratorError.contentTooLong
            }
            throw error
        }
    }
}
