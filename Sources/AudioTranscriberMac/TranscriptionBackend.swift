enum TranscriptionBackend: String, CaseIterable, Identifiable {
    case qwen3ASR = "Qwen3-ASR"
    case appleNative = "Apple Native"

    var id: String { rawValue }
}

/// Full English language names, in the exact format Qwen3-ASR's prompt
/// templating expects (confirmed by reading speech-swift's Qwen3ASR source:
/// `"language \(lang)"` is interpolated directly into the model prompt).
/// Reused verbatim from audio-transcriber's (the Python sibling project)
/// already-verified SUPPORTED_LANGUAGES list, for consistency.
enum Qwen3Languages {
    static let all: [String] = [
        "Arabic", "Cantonese", "Chinese", "Czech", "Danish", "Dutch", "English",
        "Filipino", "Finnish", "French", "German", "Greek", "Hindi", "Hungarian",
        "Indonesian", "Italian", "Japanese", "Korean", "Macedonian", "Malay",
        "Persian", "Polish", "Portuguese", "Romanian", "Russian", "Spanish",
        "Swedish", "Thai", "Turkish", "Vietnamese",
    ]
}
