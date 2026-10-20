# Audio Transcriber (native macOS)

A native SwiftUI macOS app for transcribing audio/video files, entirely
on-device — no cloud calls, no accounts, no uploading your recordings
anywhere.

## Features

- **Transcription** from any audio or video file (drag-drop or file picker),
  via one of two on-device backends:
  - **[Qwen3-ASR](https://huggingface.co/Qwen/Qwen3-ASR-1.7B-hf)**, via
    [soniqo/speech-swift](https://github.com/soniqo/speech-swift) (MLX):
    forced or auto-detected language, broad language coverage.
  - **Apple native** ([`SpeechAnalyzer`/`SpeechTranscriber`](https://developer.apple.com/videos/play/wwdc2025/277/)):
    on-device, system-managed model, no bundling required.
- **Editable, word-processor-style text** for the transcript, report, and
  translation — fix mistakes directly, the same way you would in Pages or
  Word.
- **AI Cleanup**: an on-device local LLM pass that corrects spelling/grammar
  and strips stray foreign-script leakage, without summarizing or
  rephrasing.
- **Report & Summary**: an AI-generated two-part summary and prose report
  from the transcript, in a language you choose independently of the
  transcript's own language.
- **Translation**: translate the report to another language, also via the
  local LLM.
- **Export** any tab's text as plain text, Markdown, or Word — Word export
  preserves real formatting (headings, bold, lists) rather than raw
  Markdown syntax.

## Status

Working app under active development. See open issues/milestones for
current progress.

## Requirements

- macOS 26 (Tahoe) or later, Apple Silicon
- Xcode (for the macOS 26 SDK)

## Build and run

Clone the repo:

```bash
git clone https://github.com/williamcaban/audio-transcriber-mac.git
cd audio-transcriber-mac
```

To run the app for development (builds and launches it directly):

```bash
swift run
```

To build a standalone `.app` bundle instead:

```bash
./scripts/bundle-app.sh
open "dist/Audio Transcriber.app"
```

## License

[Apache License 2.0](LICENSE).
