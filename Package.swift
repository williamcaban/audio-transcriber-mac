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
        .package(url: "https://github.com/soniqo/speech-swift", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "AudioTranscriberMac",
            dependencies: [
                .product(name: "Qwen3ASRRuntime", package: "speech-swift")
            ],
            path: "Sources/AudioTranscriberMac",
            resources: [.copy("Resources/libri_sample.wav")]
        )
    ]
)
