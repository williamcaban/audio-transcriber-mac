import Foundation

/// Only fields we can actually populate honestly are included here -- e.g.
/// no "detected language" for Qwen3-ASR, since Qwen3ASRRuntime.transcribe()
/// returns only the transcript text, not what it detected when auto-
/// detecting. "Requested language" reflects what was asked for, not a
/// confirmed detection.
struct TranscriptionMetadata {
    let fileName: String
    let fileDuration: TimeInterval?
    let fileFormatDescription: String?
    let backend: TranscriptionBackend
    let requestedLanguage: String
    let appleLocaleUsed: String?
    let processingTime: TimeInterval
    let wordCount: Int
}
