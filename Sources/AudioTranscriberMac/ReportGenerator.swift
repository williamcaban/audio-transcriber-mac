import FoundationModels

enum ReportGeneratorError: Error {
    case unavailable(String)
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

    static func generateReport(from transcript: String) async throws -> String {
        if let reason = unavailabilityReason() {
            throw ReportGeneratorError.unavailable(reason)
        }

        let session = LanguageModelSession(
            instructions: """
            You write clear, well-organized prose reports and summaries from \
            spoken-word transcripts -- sermons, classes, movies, reviews, \
            meetings, and similar recordings. Always respond in the same \
            language as the transcript.
            """
        )

        let prompt = """
        Write a report of the following transcript in two parts, in this order:

        1. A descriptive summary highlighting the important points or ideas.
        2. A more detailed prose report capturing the important ideas from \
        the transcript, in full paragraphs.

        Transcript:
        \(transcript)
        """

        let response = try await session.respond(to: prompt)
        return response.content
    }
}
