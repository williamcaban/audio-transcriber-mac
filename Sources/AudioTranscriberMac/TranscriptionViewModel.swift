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

    var reportText = ""
    var reportLanguage: String?  // nil = same as transcript
    var isGeneratingReport = false
    var reportErrorMessage: String?
    var reportStatusMessage: String?

    var translatedText = ""
    var targetLanguage: String?  // nil = none picked yet
    var isTranslating = false
    var translationErrorMessage: String?
    var translationStatusMessage: String?

    var isCleaningUp = false
    var cleaningUpTab: ContentTab?
    var cleanupErrorMessage: String?
    var cleanupStatusMessage: String?

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

    var canGenerateReport: Bool {
        !transcript.isEmpty && !isGeneratingReport
    }

    /// The transcript's language, when it's actually known (an explicit
    /// Qwen3-ASR language, or Apple Native's resolved locale) rather than
    /// left for the report LLM to guess from the content alone. Guessing
    /// was the real bug behind "Same as transcript" reliably coming back in
    /// English regardless of the transcript's real language: a small
    /// instruct model asked only to "match the source language," with
    /// nothing telling it what that is, has an observed English bias.
    /// Qwen3-ASR auto-detect (qwen3Language == nil) has no real answer
    /// here either -- the API never reports a detected language -- so that
    /// case still falls back to the same guessing behavior as before.
    var knownTranscriptLanguage: String? {
        switch backend {
        case .qwen3ASR: qwen3Language
        case .appleNative: appleLocale.appDisplayName
        }
    }

    func generateReport() {
        guard canGenerateReport else { return }
        isGeneratingReport = true
        reportErrorMessage = nil
        reportStatusMessage = "Starting..."
        let transcriptSnapshot = transcript
        let languageSnapshot = reportLanguage ?? knownTranscriptLanguage

        Task {
            do {
                reportText = try await ReportGenerator.generateReport(
                    from: transcriptSnapshot, language: languageSnapshot
                ) { [weak self] message in
                    Task { @MainActor in
                        self?.reportStatusMessage = message
                    }
                }
            } catch ReportGeneratorError.generationFailed(let message) {
                reportErrorMessage = "Couldn't generate a summary: \(message)"
            } catch is CancellationError {
                reportErrorMessage = nil
            } catch {
                reportErrorMessage = "Error: \(error)"
            }
            isGeneratingReport = false
            reportStatusMessage = nil
        }
    }

    var canTranslate: Bool {
        !reportText.isEmpty && !isTranslating && targetLanguage != nil
    }

    /// Translates the Report tab's text to `targetLanguage` using the
    /// shared local LLM -- see TranslationService.swift for why that's used
    /// instead of Apple's Translation framework.
    func startTranslation() {
        guard canTranslate, let language = targetLanguage else { return }
        isTranslating = true
        translationErrorMessage = nil
        translationStatusMessage = "Starting..."
        let textSnapshot = reportText

        Task {
            do {
                translatedText = try await TranslationService.translate(textSnapshot, to: language) { [weak self] message in
                    Task { @MainActor in
                        self?.translationStatusMessage = message
                    }
                }
            } catch TranslationServiceError.translationFailed(let message) {
                translationErrorMessage = "Couldn't translate: \(message)"
            } catch is CancellationError {
                translationErrorMessage = nil
            } catch {
                translationErrorMessage = "Error: \(error)"
            }
            isTranslating = false
            translationStatusMessage = nil
        }
    }

    /// Cleans up either tab's text in place via the shared local LLM. Only
    /// one cleanup runs at a time (the underlying model container is a
    /// single shared resource); `cleaningUpTab` tracks which tab it applies
    /// to so the busy spinner and any resulting error show up on the right
    /// tab's toolbar rather than both.
    func cleanUp(tab: ContentTab, text: String, apply: @escaping (String) -> Void) {
        guard !text.isEmpty, !isCleaningUp else { return }
        isCleaningUp = true
        cleaningUpTab = tab
        cleanupErrorMessage = nil
        cleanupStatusMessage = "Starting..."

        Task {
            do {
                let cleaned = try await TextCleanupService.cleanUp(text) { [weak self] message in
                    Task { @MainActor in self?.cleanupStatusMessage = message }
                }
                apply(cleaned)
            } catch TextCleanupError.cleanupFailed(let message) {
                cleanupErrorMessage = "Couldn't clean up text: \(message)"
            } catch is CancellationError {
                cleanupErrorMessage = nil
            } catch {
                cleanupErrorMessage = "Error: \(error)"
            }
            isCleaningUp = false
            cleanupStatusMessage = nil
        }
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
        // the "transcription completes but nothing is displayed" bug
        // chunking originally fixed. ChunkedAudioReader decodes those
        // non-overlapping 30s chunks directly off disk, one at a time,
        // rather than materializing the whole file in memory first --
        // needed after a real crash transcribing a ~8GB video file (same
        // known boundary-word tradeoff as before, and as the Python sibling
        // project's identical approach).
        let reader = try ChunkedAudioReader(url: url)
        let estimatedTotalChunks = estimatedChunkCount(forFileAt: url)

        var combined = ""
        var chunkIndex = 0
        while let chunk = try reader.nextChunk() {
            try Task.checkCancellation()
            chunkIndex += 1
            if estimatedTotalChunks > 1 {
                statusMessage = "Transcribing part \(chunkIndex) of ~\(estimatedTotalChunks)..."
            }
            let text = try await runtime.transcribe(audio: chunk, sampleRate: 16000, language: qwen3Language)
            if !combined.isEmpty, !text.isEmpty {
                combined += " "
            }
            combined += text
        }
        return combined
    }

    private func estimatedChunkCount(forFileAt url: URL) -> Int {
        guard let info = try? AudioFileInspector.inspect(url: url), info.duration > 0 else { return 1 }
        return max(1, Int((info.duration / 30).rounded(.up)))
    }

    private func runAppleNative(url: URL) async throws -> (text: String, resolvedLocale: Locale) {
        try await AppleNativeTranscriber.transcribe(fileURL: url, locale: appleLocale)
    }
}
