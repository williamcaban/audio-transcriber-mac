import AVFoundation
import Speech

enum AppleNativeTranscriberError: Error {
    case unavailable
    case localeUnsupported
}

// Apple's SpeechAnalyzer/SpeechTranscriber (macOS 26+) has no public GitHub
// source to read the way speech-swift does -- this was reconstructed from
// Apple's WWDC25 session and third-party write-ups, then corrected once
// against a real compile error (SpeechTranscriber.Result's property is
// `isFinal`, not the originally-guessed `isVolatile`; everything else --
// AssetInventory's status cases, analyzeSequence/finalizeAndFinish
// signatures, the Result type's other properties -- matched on the first
// try). CI only proves it builds; actual behavior still needs William's
// Mac.
//
// Still unconfirmed: whether this requires a speech-recognition usage
// description/authorization prompt even for transcribing a local file
// (rather than live mic capture). This bare SPM executable has no
// Info.plist to add an NSSpeechRecognitionUsageDescription key to if one
// turns out to be required -- if William hits an authorization/permission
// error, that's the next thing to investigate, likely needing a proper
// Info.plist via an INFOPLIST_FILE build setting or Package.swift's
// `resources`/linker-settings-based embedding.
enum AppleNativeTranscriber {
    /// Locales SpeechTranscriber can transcribe. Apple's API always
    /// requires picking one specific locale -- there is no auto-detect
    /// mode, unlike Qwen3-ASR. Surfaced in the UI so that asymmetry is
    /// explained, not hidden.
    static func supportedLocales() async -> [Locale] {
        Array(await SpeechTranscriber.supportedLocales)
    }

    static func transcribe(fileURL: URL, locale: Locale) async throws -> (text: String, resolvedLocale: Locale) {
        guard SpeechTranscriber.isAvailable else {
            throw AppleNativeTranscriberError.unavailable
        }
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw AppleNativeTranscriberError.localeUnsupported
        }

        let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .transcription)

        if await AssetInventory.status(forModules: [transcriber]) != .installed {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: fileURL)

        // The results async sequence must be consumed concurrently with
        // feeding the file, not after -- `finalizeAndFinishThroughEndOfInput`
        // is what lets the `for try await` loop below know there's no more
        // audio coming and exit, rather than hanging forever.
        async let collected: String = {
            var full = ""
            for try await result in transcriber.results where result.isFinal {
                full += String(result.text.characters)
            }
            return full
        }()

        _ = try await analyzer.analyzeSequence(from: audioFile)
        try await analyzer.finalizeAndFinishThroughEndOfInput()

        return (try await collected, supportedLocale)
    }
}
