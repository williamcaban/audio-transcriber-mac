import Translation

enum TranslationRunnerError: Error {
    case translationFailed(String)
}

/// Runs chunked translation using a `TranslationSession` handed to us by
/// SwiftUI's `.translationTask` modifier -- kept as a plain, non-actor-
/// isolated enum (like ReportGenerator/TextCleanupService) rather than a
/// method on the main-actor-isolated view model, since `TranslationSession`
/// is non-Sendable and its `translate` method runs on its own concurrent
/// executor: calling it from any main-actor-isolated context (directly, or
/// by handing `session` to one) is flagged as a real data-race risk by the
/// compiler, not just a style nit.
enum TranslationRunner {
    private static let maxChunkCharacters = 20000

    static func translate(
        _ text: String,
        session: TranslationSession,
        onStatusUpdate: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        do {
            // Translation's own practical context limit per call isn't
            // documented; chunking is kept as a safety net for very long
            // reports, same budget as ReportGenerator's local-LLM chunking.
            // Map-only (not map-reduce): each chunk is translated
            // independently and concatenated back in order.
            let chunks = chunk(text, maxCharacters: maxChunkCharacters)
            var translated: [String] = []
            for (index, chunk) in chunks.enumerated() {
                try Task.checkCancellation()
                if chunks.count > 1 {
                    onStatusUpdate?("Translating part \(index + 1) of \(chunks.count)...")
                }
                let response = try await session.translate(chunk)
                translated.append(response.targetText)
            }
            return translated
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: " ")
        } catch let error as CancellationError {
            throw error
        } catch {
            throw TranslationRunnerError.translationFailed("\(error)")
        }
    }

    // Same sentence-boundary-preferring chunking as ReportGenerator's (kept
    // separate rather than shared, since the two evolved independently and
    // there's no current need to unify them).
    private static func chunk(_ text: String, maxCharacters: Int) -> [String] {
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
