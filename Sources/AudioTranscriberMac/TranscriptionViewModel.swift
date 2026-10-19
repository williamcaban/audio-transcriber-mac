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
    var lastMetadata: TranscriptionMetadata?

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
        lastMetadata = nil
        statusMessage = "Starting..."

        let startedAt = Date()

        currentTask = Task {
            do {
                let text: String
                var appleLocaleUsed: String?

                switch backend {
                case .qwen3ASR:
                    text = try await runQwen3(url: url)
                case .appleNative:
                    let (resultText, resolvedLocale) = try await runAppleNative(url: url)
                    text = resultText
                    appleLocaleUsed = displayName(for: resolvedLocale)
                }

                transcript = text
                statusMessage = "Done"
                lastMetadata = buildMetadata(
                    url: url, text: text, appleLocaleUsed: appleLocaleUsed, startedAt: startedAt
                )
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

    private func buildMetadata(
        url: URL, text: String, appleLocaleUsed: String?, startedAt: Date
    ) -> TranscriptionMetadata {
        let fileInfo = try? AudioFileInspector.inspect(url: url)
        let requestedLanguage: String =
            switch backend {
            case .qwen3ASR: qwen3Language ?? "Auto-detect"
            case .appleNative: displayName(for: appleLocale)
            }

        return TranscriptionMetadata(
            fileName: url.lastPathComponent,
            fileDuration: fileInfo?.duration,
            fileFormatDescription: fileInfo.map { "\(Int($0.sampleRate)) Hz, \($0.channelCount)ch" },
            backend: backend,
            requestedLanguage: requestedLanguage,
            appleLocaleUsed: appleLocaleUsed,
            processingTime: Date().timeIntervalSince(startedAt),
            wordCount: text.split(whereSeparator: \.isWhitespace).count
        )
    }

    private func displayName(for locale: Locale) -> String {
        locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
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

    private func runAppleNative(url: URL) async throws -> (text: String, resolvedLocale: Locale) {
        statusMessage = "Transcribing (Apple native)..."
        return try await AppleNativeTranscriber.transcribe(fileURL: url, locale: appleLocale)
    }
}
