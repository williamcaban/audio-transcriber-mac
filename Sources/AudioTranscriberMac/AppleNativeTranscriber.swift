import AVFoundation
import Speech

enum AppleNativeTranscriberError: Error {
    case unavailable
    case localeUnsupported
}

// Apple's SpeechAnalyzer/SpeechTranscriber (macOS 26+) has no public GitHub
// source to read the way speech-swift does -- this is reconstructed from
// Apple's WWDC25 session and third-party write-ups, not verified by
// compiling it myself (no local Xcode/macOS access). CI only proves the
// Qwen3-ASR path builds against a real dependency graph; this file's
// correctness can only be confirmed by William building on his Mac. If
// exact API names (e.g. AssetInventory's status enum cases) turn out
// slightly different, that's expected and should be a quick fix once the
// real compiler error is visible.
//
// Also unconfirmed: whether this requires a speech-recognition usage
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

    static func transcribe(fileURL: URL, locale: Locale) async throws -> String {
        guard await SpeechTranscriber.isAvailable else {
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
            for try await result in transcriber.results where !result.isVolatile {
                full += String(result.text.characters)
            }
            return full
        }()

        try await analyzer.analyzeSequence(from: audioFile)
        try await analyzer.finalizeAndFinishThroughEndOfInput()

        return try await collected
    }
}
