enum ReportGeneratorError: Error {
    case generationFailed(String)
}

/// Generates a prose report and summary from a transcript using the shared
/// local on-device LLM (see LocalLLM.swift), replacing an earlier
/// implementation built on Apple's Foundation Models framework -- which had
/// two real, reported problems: a mandatory, non-configurable content-
/// safety guardrail that flagged ordinary transcripts, and a hard
/// 4096-token context window that failed outright on normal-length
/// recordings. The local model has a much larger context window, but the
/// map-reduce chunking below is kept as a safety net for very long files
/// (there's no public tokenizer here to count exactly ahead of time).
enum ReportGenerator {
    // Generous relative to the local model's much larger context window
    // (vs. Apple's hard 4096-token limit that originally forced a tight
    // budget here) -- kept well short of it regardless, to leave headroom
    // for less token-efficient scripts (CJK, Thai, etc) plus the
    // instructions/prompt wrapper and the response itself.
    private static let maxChunkCharacters = 20000

    /// Generates the final two-part summary + prose report. Transcripts
    /// that fit in one model call go straight through; longer ones are
    /// map-reduced -- summarized in bounded chunks, then those summaries
    /// combined (recursively, if even the combined summaries are still too
    /// large) before the final report is written. Same bounded-window-
    /// chunking shape already used for Qwen3-ASR's fixed audio window,
    /// just applied to this model's (much larger, but still finite)
    /// context window instead.
    static func generateReport(
        from transcript: String,
        onStatusUpdate: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        do {
            // Loaded eagerly, with its own status, before any chunking or
            // summarization work -- otherwise the ~2.3GB download would
            // happen silently inside whichever call happens to trigger it
            // first (summarizeChunk for a long transcript, writeReport for
            // a short one), looking stuck with no visible progress. Exactly
            // the class of bug already hit and fixed once for Qwen3-ASR.
            _ = try await LocalLLM.loadContainer { progress, message in
                onStatusUpdate?(progress > 0 ? "\(message) (\(Int(progress * 100))%)" : message)
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
        } catch let error as CancellationError {
            throw error
        } catch {
            throw ReportGeneratorError.generationFailed("\(error)")
        }
    }

    private static func chunkText(_ text: String) -> [String] {
        TextChunker.chunk(text, maxCharacters: maxChunkCharacters)
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
        try await LocalLLM.respond(
            instructions: """
            You extract the key points from part of a longer transcript or \
            set of summaries. Respond with concise bullet points only, in \
            the same language as the text. This is only one part of a \
            larger whole, so don't summarize it as if it were complete on \
            its own.
            """,
            prompt: "Content:\n\(chunk)"
        )
    }

    private static func writeReport(from content: String) async throws -> String {
        try await LocalLLM.respond(
            instructions: """
            You write clear, well-organized prose reports and summaries from \
            spoken-word transcripts -- sermons, classes, movies, reviews, \
            meetings, and similar recordings. Always respond in the same \
            language as the source material.
            """,
            prompt: """
            Write a report of the following in two parts, in this order:

            1. A descriptive summary highlighting the important points or ideas.
            2. A more detailed prose report capturing the important ideas, in \
            full paragraphs.

            Content:
            \(content)
            """
        )
    }
}
