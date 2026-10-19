import Foundation
import Observation
import Qwen3ASRRuntime

enum TranscriptionViewModelError: Error {
    case backendNotReady
}

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

    var qwen3LoadState: BackendLoadState = .notLoaded
    var appleLoadState: BackendLoadState = .notLoaded

    private var currentTask: Task<Void, Never>?
    private var qwen3Runtime: Qwen3ASRRuntime?

    func loadState(for backend: TranscriptionBackend) -> BackendLoadState {
        switch backend {
        case .qwen3ASR: qwen3LoadState
        case .appleNative: appleLoadState
        }
    }

    func loadAvailableAppleLocales() {
        Task {
            availableAppleLocales = await AppleNativeTranscriber.supportedLocales()
                .sorted { $0.identifier(.bcp47) < $1.identifier(.bcp47) }
        }
    }

    /// Eagerly downloads/loads the given backend's model, rather than
    /// letting it happen lazily inside startTranscription() -- that lazy
    /// path caused a real, reported bug: the download-progress callback
    /// kept firing into the shared status line well after transcription had
    /// visibly "started", so the UI got stuck showing a stale "Ready (100%)"
    /// download message while real transcription work was still underway.
    /// Call this on backend selection (and on the initial default backend),
    /// not on every transcribe -- it's a no-op once already ready.
    func prepareBackend(_ backend: TranscriptionBackend) {
        switch backend {
        case .qwen3ASR: prepareQwen3()
        case .appleNative: prepareAppleNative()
        }
    }

    var canTranscribe: Bool {
        selectedFileURL != nil && !isTranscribing && loadState(for: backend) == .ready
    }

    func startTranscription() {
        guard let url = selectedFileURL, !isTranscribing, loadState(for: backend) == .ready else { return }

        isTranscribing = true
        transcript = ""
        lastMetadata = nil
        statusMessage = "Transcribing..."

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
                    appleLocaleUsed = resolvedLocale.appDisplayName
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

    private func prepareQwen3() {
        if qwen3Runtime != nil {
            qwen3LoadState = .ready
            return
        }
        if case .loading = qwen3LoadState { return }

        qwen3LoadState = .loading(progress: 0, message: "Starting...")
        let runtime = Qwen3ASRRuntime(descriptor: Qwen3ASRDescriptors.large) { [weak self] progress, message in
            Task { @MainActor in
                self?.qwen3LoadState = .loading(progress: progress, message: message)
            }
        }

        Task {
            do {
                try await runtime.prepare()
                qwen3Runtime = runtime
                qwen3LoadState = .ready
            } catch {
                qwen3LoadState = .failed("\(error)")
            }
        }
    }

    private func prepareAppleNative() {
        if case .loading = appleLoadState { return }

        appleLoadState = .loading(progress: 0, message: "Checking language model...")
        let locale = appleLocale

        Task {
            do {
                // AssetInstallationRequest exposes a KVO Progress object,
                // not an async progress callback like Qwen3ASRRuntime --
                // not wired up here, so this shows as indeterminate rather
                // than a real percentage. Apple's locale assets are
                // typically much smaller than Qwen3-ASR's MLX checkpoint
                // and may already be cached from Dictation/Siri use, so
                // this is usually fast regardless.
                _ = try await AppleNativeTranscriber.ensureModelInstalled(locale: locale)
                if locale == appleLocale {
                    appleLoadState = .ready
                }
            } catch {
                if locale == appleLocale {
                    appleLoadState = .failed("\(error)")
                }
            }
        }
    }

    private func buildMetadata(
        url: URL, text: String, appleLocaleUsed: String?, startedAt: Date
    ) -> TranscriptionMetadata {
        let fileInfo = try? AudioFileInspector.inspect(url: url)
        let requestedLanguage: String =
            switch backend {
            case .qwen3ASR: qwen3Language ?? "Auto-detect"
            case .appleNative: appleLocale.appDisplayName
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

    private func runQwen3(url: URL) async throws -> String {
        let samples = try AudioLoader.loadMonoFloatSamples(url: url)
        try Task.checkCancellation()
        guard let runtime = qwen3Runtime else {
            // Shouldn't happen: canTranscribe/startTranscription both gate
            // on loadState == .ready, which is only set once qwen3Runtime
            // is non-nil. Fall back to on-the-spot loading rather than
            // crashing if this invariant is ever violated.
            prepareQwen3()
            throw TranscriptionViewModelError.backendNotReady
        }
        // Qwen3-ASR's audio encoder has a fixed ~30s window -- sending a
        // whole long file in one call silently produces no usable output
        // past that window rather than erroring clearly, which is exactly
        // the "transcription completes but nothing is displayed" bug this
        // chunking fixes. Non-overlapping 30s chunks match the Python
        // sibling project's identical, documented approach (including its
        // known tradeoff: a word spanning a chunk boundary can come out
        // slightly garbled).
        let chunks = AudioLoader.chunk(samples, bySeconds: 30, sampleRate: 16000)
        var combined = ""
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            if chunks.count > 1 {
                statusMessage = "Transcribing part \(index + 1) of \(chunks.count)..."
            }
            let text = try await runtime.transcribe(audio: chunk, sampleRate: 16000, language: qwen3Language)
            if !combined.isEmpty, !text.isEmpty {
                combined += " "
            }
            combined += text
        }
        return combined
    }

    private func runAppleNative(url: URL) async throws -> (text: String, resolvedLocale: Locale) {
        try await AppleNativeTranscriber.transcribe(fileURL: url, locale: appleLocale)
    }
}
