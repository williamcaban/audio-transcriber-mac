# Audio Transcriber (native macOS)

A native SwiftUI macOS app that transcribes audio/video files to Markdown
(and, later, Word), using two on-device backends:

- **[Qwen3-ASR](https://huggingface.co/Qwen/Qwen3-ASR-1.7B-hf)**, via
  [soniqo/speech-swift](https://github.com/soniqo/speech-swift) (MLX):
  forced or auto-detected language, broad language coverage.
- **Apple native** ([`SpeechAnalyzer`/`SpeechTranscriber`](https://developer.apple.com/videos/play/wwdc2025/277/)):
  on-device, system-managed model, no bundling required.

This is a ground-up native rewrite, not a wrapper around a server. See
[williamcaban/audio-transcriber](https://github.com/williamcaban/audio-transcriber)
for the cross-platform FastAPI version (Linux/container/Parakeet TDT), which
this project does not replace.

## Status

Early scaffold — no working build yet. See open issues/milestones for
current progress.

## Requirements

- macOS 26 (Tahoe) or later, Apple Silicon
- Xcode (for the macOS 26 SDK)

## License

[Apache License 2.0](LICENSE).
