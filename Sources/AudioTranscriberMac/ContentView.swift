import Qwen3ASRRuntime
import SwiftUI

struct ContentView: View {
    @State private var transcript = ""
    @State private var statusMessage = "Idle"
    @State private var isTranscribing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio Transcriber")
                .font(.title)

            Button(isTranscribing ? "Transcribing..." : "Transcribe bundled test file") {
                runTranscription()
            }
            .disabled(isTranscribing)

            Text(statusMessage)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(transcript)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 320)
    }

    // Milestone-3 proof of life: this hardcodes the bundled LibriSpeech
    // fixture and the 1.7B/int8 descriptor rather than exposing a file
    // picker or model choice -- those land in the real UI milestone. The
    // point here is only to confirm Qwen3ASRRuntime actually downloads,
    // loads, and transcribes correctly end to end.
    private func runTranscription() {
        guard let url = Bundle.module.url(forResource: "libri_sample", withExtension: "wav") else {
            statusMessage = "Bundled test fixture not found"
            return
        }

        isTranscribing = true
        statusMessage = "Loading audio..."
        transcript = ""

        Task {
            do {
                let samples = try AudioLoader.loadMonoFloatSamples(url: url)

                await MainActor.run { statusMessage = "Loading model (first run downloads it)..." }
                let runtime = Qwen3ASRRuntime(descriptor: Qwen3ASRDescriptors.large) { progress, message in
                    Task { @MainActor in
                        statusMessage = "\(message) (\(Int(progress * 100))%)"
                    }
                }

                await MainActor.run { statusMessage = "Transcribing..." }
                let text = try await runtime.transcribe(audio: samples, sampleRate: 16000)

                await MainActor.run {
                    transcript = text
                    statusMessage = "Done"
                    isTranscribing = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Error: \(error)"
                    isTranscribing = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
