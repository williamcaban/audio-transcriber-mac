import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = TranscriptionViewModel()
    @State private var showExportError = false
    @State private var isDropTargeted = false
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            dropZone
            settingsCard
            actionBar
            statusBar
            transcriptCard
            if showDetails, let metadata = viewModel.lastMetadata {
                detailsCard(metadata)
            }
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 540)
        .onAppear { viewModel.loadAvailableAppleLocales() }
        .alert("Export failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Audio Transcriber")
                    .font(.title2.bold())
                Text("On-device transcription with Qwen3-ASR or Apple's native speech engine")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dropZone: some View {
        Button(action: presentFilePicker) {
            VStack(spacing: 8) {
                if let url = viewModel.selectedFileURL {
                    Image(systemName: "doc.badge.checkmark")
                        .font(.system(size: 32))
                        .foregroundStyle(.tint)
                    Text(url.lastPathComponent)
                        .font(.headline)
                    Text("Click or drop another file to replace")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Drop an audio or video file here")
                        .font(.headline)
                    Text("or click to browse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(32)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
        )
        .dropDestination(for: URL.self) { items, _ in
            guard let url = items.first else { return false }
            viewModel.selectedFileURL = url
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Backend", selection: $viewModel.backend) {
                ForEach(TranscriptionBackend.allCases) { backend in
                    Text(backend.rawValue).tag(backend)
                }
            }
            .pickerStyle(.segmented)

            languagePicker
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
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
        case .appleNative:
            Picker("Language", selection: $viewModel.appleLocale) {
                ForEach(viewModel.availableAppleLocales, id: \.identifier) { locale in
                    Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                        .tag(locale)
                }
            }
            .disabled(viewModel.availableAppleLocales.isEmpty)
        }
    }

    private var actionBar: some View {
        HStack {
            Button {
                viewModel.startTranscription()
            } label: {
                Label(viewModel.isTranscribing ? "Transcribing..." : "Transcribe", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canTranscribe)

            if viewModel.isTranscribing {
                Button(role: .destructive) {
                    viewModel.cancelTranscription()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
            }

            Spacer()

            Button {
                showDetails.toggle()
            } label: {
                Label("Details", systemImage: "info.circle")
            }
            .disabled(viewModel.lastMetadata == nil)

            Button {
                copyTranscript()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(viewModel.transcript.isEmpty)

            Button {
                exportMarkdown()
            } label: {
                Label("Export...", systemImage: "square.and.arrow.down")
            }
            .disabled(viewModel.transcript.isEmpty)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if viewModel.isTranscribing {
                ProgressView()
                    .controlSize(.small)
            }
            Text(viewModel.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var transcriptCard: some View {
        ScrollView {
            Text(viewModel.transcript.isEmpty ? "Transcript will appear here." : viewModel.transcript)
                .textSelection(.enabled)
                .foregroundStyle(viewModel.transcript.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.2))
        )
        .frame(maxHeight: .infinity)
    }

    private func detailsCard(_ metadata: TranscriptionMetadata) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("File").foregroundStyle(.secondary)
                    Text(metadata.fileName)
                }
                if let duration = metadata.fileDuration {
                    GridRow {
                        Text("Duration").foregroundStyle(.secondary)
                        Text(formatDuration(duration))
                    }
                }
                if let format = metadata.fileFormatDescription {
                    GridRow {
                        Text("Format").foregroundStyle(.secondary)
                        Text(format)
                    }
                }
                GridRow {
                    Text("Backend").foregroundStyle(.secondary)
                    Text(metadata.backend.rawValue)
                }
                GridRow {
                    Text("Language").foregroundStyle(.secondary)
                    Text(metadata.requestedLanguage)
                }
                if let locale = metadata.appleLocaleUsed {
                    GridRow {
                        Text("Locale used").foregroundStyle(.secondary)
                        Text(locale)
                    }
                }
                GridRow {
                    Text("Processing time").foregroundStyle(.secondary)
                    Text(formatDuration(metadata.processingTime))
                }
                GridRow {
                    Text("Word count").foregroundStyle(.secondary)
                    Text("\(metadata.wordCount)")
                }
            }
            .font(.callout)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: interval) ?? "\(Int(interval))s"
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
