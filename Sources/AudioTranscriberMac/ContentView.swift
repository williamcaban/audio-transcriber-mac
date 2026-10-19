import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = TranscriptionViewModel()
    @State private var showExportError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio Transcriber")
                .font(.title)

            filePicker
            backendPicker
            languagePicker

            HStack {
                Button(viewModel.isTranscribing ? "Transcribing..." : "Transcribe") {
                    viewModel.startTranscription()
                }
                .disabled(!viewModel.canTranscribe)

                if viewModel.isTranscribing {
                    Button("Cancel") { viewModel.cancelTranscription() }
                }

                Spacer()

                Button("Copy") { copyTranscript() }
                    .disabled(viewModel.transcript.isEmpty)
                Button("Export Markdown...") { exportMarkdown() }
                    .disabled(viewModel.transcript.isEmpty)
            }

            Text(viewModel.statusMessage)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(viewModel.transcript)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 420)
        .onAppear { viewModel.loadAvailableAppleLocales() }
        .alert("Export failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        }
    }

    private var filePicker: some View {
        HStack {
            Button("Choose File...") { presentFilePicker() }
            Text(viewModel.selectedFileURL?.lastPathComponent ?? "No file selected")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var backendPicker: some View {
        Picker("Backend", selection: $viewModel.backend) {
            ForEach(TranscriptionBackend.allCases) { backend in
                Text(backend.rawValue).tag(backend)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 360)
    }

    // Each backend's real language capability is different -- Qwen3-ASR can
    // genuinely force a language or auto-detect; Apple's SpeechAnalyzer
    // always requires picking one specific locale, with no auto-detect
    // mode. Showing different controls per backend reflects that honestly
    // rather than papering over the asymmetry.
    @ViewBuilder
    private var languagePicker: some View {
        switch viewModel.backend {
        case .qwen3ASR:
            Picker("Language", selection: $viewModel.qwen3Language) {
                Text("Auto-detect").tag(String?.none)
                ForEach(Qwen3Languages.all, id: \.self) { language in
                    Text(language).tag(String?.some(language))
                }
            }
            .frame(maxWidth: 280)
        case .appleNative:
            Picker("Language", selection: $viewModel.appleLocale) {
                ForEach(viewModel.availableAppleLocales, id: \.identifier) { locale in
                    Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                        .tag(locale)
                }
            }
            .frame(maxWidth: 280)
            .disabled(viewModel.availableAppleLocales.isEmpty)
        }
    }

    private func presentFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Movie]
        if panel.runModal() == .OK {
            viewModel.selectedFileURL = panel.url
        }
    }

    private func copyTranscript() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(viewModel.transcript, forType: .string)
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        let baseName = viewModel.selectedFileURL?.deletingPathExtension().lastPathComponent ?? "transcript"
        panel.nameFieldStringValue = "\(baseName).md"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try viewModel.transcript.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            showExportError = true
        }
    }
}

#Preview {
    ContentView()
}
