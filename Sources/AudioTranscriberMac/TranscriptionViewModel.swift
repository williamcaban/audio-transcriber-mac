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
    var isGeneratingReport = false
    var reportErrorMessage: String?
    var reportStatusMessage: String?

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

    /// Best-effort BCP-47 code for spell-checking the transcript, honestly
    /// reflecting what's actually known: Qwen3-ASR's forced language (if
    /// set) or Apple Native's resolved locale. When Qwen3 is in auto-detect
    /// mode, there's no real "detected language" to report (the API never
    /// returns one), so this falls back to the system's current language
    /// rather than fabricating one.
    var spellCheckLanguageCode: String? {
        switch backend {
        case .qwen3ASR:
            if let language = qwen3Language {
                return Qwen3Languages.spellCheckCodes[language]
            }
            return Locale.current.language.languageCode?.identifier
        case .appleNative:
            return appleLocale.identifier
        }
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

    func generateReport() {
        guard canGenerateReport else { return }
        isGeneratingReport = true
        reportErrorMessage = nil
        reportStatusMessage = "Starting..."
        let transcriptSnapshot = transcript

        Task {
            do {
                reportText = try await ReportGenerator.generateReport(from: transcriptSnapshot) { [weak self] message in
                    Task { @MainActor in
                        self?.reportStatusMessage = message
                    }
                }
            } catch ReportGeneratorError.unavailable(let message) {
                reportErrorMessage = message
            } catch ReportGeneratorError.guardrailFlagged {
                reportErrorMessage = "Apple's on-device safety filter flagged this transcript and couldn't generate a summary. This can happen even with ordinary content -- you can write the summary manually in this tab, or try again."
            } catch ReportGeneratorError.contentTooLong {
                reportErrorMessage = "This transcript is too long to summarize, even in parts. Try a shorter recording."
            } catch {
                reportErrorMessage = "Error: \(error)"
            }
            isGeneratingReport = false
            reportStatusMessage = nil
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
