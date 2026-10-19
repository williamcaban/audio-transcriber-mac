import Foundation
import Observation
import Qwen3ASRRuntime

@MainActor
@Observable
final class TranscriptionViewModel {
    var selectedFileURL: URL?
    var backend: TranscriptionBackend = .qwen3ASR
    var qwen3Language: String?  // nil = auto-detect
    var appleLocale = Locale(identifier: "en-US")
    var availableAppleLocales: [Locale] = []
    var transcript = ""
    var statusMessage = "Idle"
    var isTranscribing = false

    private var currentTask: Task<Void, Never>?
    private var qwen3Runtime: Qwen3ASRRuntime?

    func loadAvailableAppleLocales() {
        Task {
            availableAppleLocales = await AppleNativeTranscriber.supportedLocales()
                .sorted { $0.identifier(.bcp47) < $1.identifier(.bcp47) }
        }
    }

    var canTranscribe: Bool { selectedFileURL != nil && !isTranscribing }

    func startTranscription() {
        guard let url = selectedFileURL, !isTranscribing else { return }

        isTranscribing = true
        transcript = ""
        statusMessage = "Starting..."

        currentTask = Task {
            do {
                let text: String
                switch backend {
                case .qwen3ASR:
                    text = try await runQwen3(url: url)
                case .appleNative:
                    text = try await runAppleNative(url: url)
                }
                transcript = text
                statusMessage = "Done"
            } catch is CancellationError {
                statusMessage = "Cancelled"
            } catch {
                statusMessage = "Error: \(error)"
            }
            isTranscribing = false
        }
    }

    func cancelTranscription() {
        currentTask?.cancel()
    }

    private func runQwen3(url: URL) async throws -> String {
        let samples = try AudioLoader.loadMonoFloatSamples(url: url)
        try Task.checkCancellation()

        let runtime: Qwen3ASRRuntime
        if let existing = qwen3Runtime {
            runtime = existing
        } else {
            statusMessage = "Loading model (first run downloads it)..."
            runtime = Qwen3ASRRuntime(descriptor: Qwen3ASRDescriptors.large) { [weak self] progress, message in
                Task { @MainActor in
                    self?.statusMessage = "\(message) (\(Int(progress * 100))%)"
                }
            }
            qwen3Runtime = runtime
        }

        try Task.checkCancellation()
        statusMessage = "Transcribing..."
        return try await runtime.transcribe(audio: samples, sampleRate: 16000, language: qwen3Language)
    }

    private func runAppleNative(url: URL) async throws -> String {
        statusMessage = "Transcribing (Apple native)..."
        return try await AppleNativeTranscriber.transcribe(fileURL: url, locale: appleLocale)
    }
}
