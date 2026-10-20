// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AudioTranscriberMac",
    platforms: [.macOS(.v26)],
    dependencies: [
        // speech-swift is pre-1.0 and iterating quickly; its own README
        // recommends tracking `main` rather than pinning a tag. Revisit
        // pinning to an exact tag once the APIs this app depends on
        // (Qwen3ASRRuntime, SpeechUI) stabilize.
        .package(url: "https://github.com/soniqo/speech-swift", branch: "main"),
        // Local on-device LLM for Report & Summary and AI text cleanup,
        // replacing Apple's Foundation Models framework (which had a
        // mandatory, non-configurable content-safety guardrail that
        // flagged ordinary transcripts, and a hard 4096-token context
        // window that failed on normal-length recordings).
        //
        // speech-swift (tracked at `main`, above) pins this exact
        // dependency itself -- currently `.exact("3.31.4")` -- so this
        // uses a broad `from:` range (upToNextMajor) rather than
        // mlx-swift-lm's own README-recommended `.upToNextMinor(from:
        // "3.32.3")`, specifically so a future speech-swift update that
        // bumps its own pin doesn't reintroduce an unresolvable version
        // conflict between the two.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.4"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "AudioTranscriberMac",
            dependencies: [
                .product(name: "Qwen3ASRRuntime", package: "speech-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            path: "Sources/AudioTranscriberMac",
            resources: [.copy("Resources/libri_sample.wav")]
        )
    ]
)
