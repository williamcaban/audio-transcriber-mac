import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// A shared on-device instruct model used for both the Report & Summary
/// feature and AI-assisted text cleanup, running entirely locally via MLX
/// (mlx-swift-lm) -- the same approach Qwen3-ASR already uses for
/// transcription, just for text generation instead.
///
/// Chosen specifically to replace Apple's Foundation Models framework,
/// which had two real, reported problems in this app: a mandatory,
/// non-configurable content-safety guardrail that flagged ordinary
/// transcripts, and a hard 4096-token context window that failed outright
/// on normal-length recordings.
@MainActor
enum LocalLLM {
    /// mlx-community's instruction-tuned, 4-bit-quantized Qwen3 -- the same
    /// model family already used for ASR (Qwen3Languages' language list
    /// comes from that family), Apache-2.0 licensed, ~2.3GB download.
    static let modelID = "mlx-community/Qwen3-4B-Instruct-2507-4bit"

    private static let configuration = ModelConfiguration(id: modelID)
    private static var cachedContainer: ModelContainer?

    /// Downloads (on first use) and loads the shared model container,
    /// caching it for subsequent calls. Safe to call repeatedly.
    static func loadContainer(
        onProgress: (@Sendable (Double, String) -> Void)? = nil
    ) async throws -> ModelContainer {
        if let cachedContainer { return cachedContainer }
        let container = try await #huggingFaceLoadModelContainer(
            configuration: configuration
        ) { progress in
            onProgress?(
                progress.fractionCompleted,
                progress.localizedDescription ?? "Downloading language model..."
            )
        }
        cachedContainer = container
        return container
    }

    /// Runs a single-turn prompt against the model with the given system
    /// instructions, returning its full text response. Each call creates
    /// its own ``ChatSession`` -- the calls this app makes (report
    /// generation, chunk summarization, text cleanup) are independent
    /// one-shot prompts, not a multi-turn conversation, so there's no
    /// reason to share session state (and KV-cache growth) across them.
    static func respond(
        instructions: String,
        prompt: String,
        onProgress: (@Sendable (Double, String) -> Void)? = nil
    ) async throws -> String {
        let container = try await loadContainer(onProgress: onProgress)
        let session = ChatSession(container, instructions: instructions)
        return try await session.respond(to: prompt)
    }
}
