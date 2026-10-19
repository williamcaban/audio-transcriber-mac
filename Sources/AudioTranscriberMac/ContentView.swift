import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = TranscriptionViewModel()
    @State private var showExportError = false
    @State private var isDropTargeted = false
    @State private var showDetails = false
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if showSettings {
                settingsSection
            }
            dropZone
            languagePicker
            actionBar
            statusBar
            transcriptCard
            if showDetails, let metadata = viewModel.lastMetadata {
                detailsCard(metadata)
            }
        }
        .padding(24)
        .frame(minWidth: 680, minHeight: 580)
        .onAppear {
            viewModel.loadAvailableAppleLocales()
            viewModel.prepareBackend(viewModel.backend)
        }
        .onChange(of: viewModel.backend) { _, newBackend in
            viewModel.prepareBackend(newBackend)
        }
        .onChange(of: viewModel.appleLocale) {
            if viewModel.backend == .appleNative {
                viewModel.prepareBackend(.appleNative)
            }
        }
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
                Text("On-device AI-powered transcriptions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(showSettings ? Color.accentColor : .secondary)
            .help("Settings")
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

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            backendRow
            if let caption = backendLoadCaption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // Each button both selects and (if needed) triggers download of its
    // backend's model, with its own inline state -- not downloaded,
    // downloading with progress, ready, or failed. This replaces a plain
    // segmented picker specifically so both backends' download states are
    // visible at once, at the row where the backend is chosen, rather than
    // conflated into the single shared status line below (which is what
    // caused a real, reported bug: a stale "Ready (100%)" download message
    // sitting on screen while actual transcription was still in progress).
    private var backendRow: some View {
        HStack(spacing: 10) {
            ForEach(TranscriptionBackend.allCases) { backend in
                backendButton(backend)
            }
        }
    }

    private func backendButton(_ backend: TranscriptionBackend) -> some View {
        let isSelected = viewModel.backend == backend
        return Button {
            viewModel.backend = backend
            viewModel.prepareBackend(backend)
        } label: {
            HStack(spacing: 8) {
                Text(backend.rawValue)
                    .font(.body.weight(.medium))
                stateIndicator(viewModel.loadState(for: backend))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private func stateIndicator(_ state: BackendLoadState) -> some View {
        switch state {
        case .notLoaded:
            Image(systemName: "icloud.and.arrow.down")
                .foregroundStyle(.secondary)
        case .loading(let progress, _):
            if progress > 0 {
                ProgressView(value: progress)
                    .frame(width: 36)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var backendLoadCaption: String? {
        switch viewModel.loadState(for: viewModel.backend) {
        case .notLoaded, .ready:
            nil
        case .loading(let progress, let message):
            progress > 0 ? "\(message) (\(Int(progress * 100))%)" : message
        case .failed(let reason):
            "Failed to load: \(reason)"
        }
    }

    // Each backend's real language capability is different -- Qwen3-ASR can
    // genuinely force a language or auto-detect; Apple's SpeechAnalyzer
    // always requires picking one specific locale, with no auto-detect
    // mode. Showing different controls per backend reflects that honestly
    // rather than papering over the asymmetry.
    @ViewBuilder
    private var languagePicker: some View {
        Group {
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.startTranscription()
            } label: {
                Label(viewModel.isTranscribing ? "Transcribing..." : "Transcribe", systemImage: "play.fill")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canTranscribe)

            if viewModel.isTranscribing {
                Button(role: .destructive) {
                    viewModel.cancelTranscription()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .controlSize(.large)
            }

            Spacer()

            Button {
                showDetails.toggle()
            } label: {
                Label("Details", systemImage: "info.circle")
            }
            .controlSize(.large)
            .disabled(viewModel.lastMetadata == nil)

            Button {
                copyTranscript()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .controlSize(.large)
            .disabled(viewModel.transcript.isEmpty)

            Menu {
                ForEach(ExportFormat.allCases) { format in
                    Button("\(format.rawValue) (.\(format.fileExtension))") {
                        exportTranscript(as: format)
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.down")
            }
            .controlSize(.large)
            .disabled(viewModel.transcript.isEmpty)
        }
    }

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                if viewModel.isTranscribing {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(viewModel.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if viewModel.isTranscribing {
                Text("Longer files can take several minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

    // .docx already opens natively in Pages -- no separate Pages-specific
    // export format needed to cover that case.
    private func exportTranscript(as format: ExportFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        let baseName = viewModel.selectedFileURL?.deletingPathExtension().lastPathComponent ?? "transcript"
        panel.nameFieldStringValue = "\(baseName).\(format.fileExtension)"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            switch format {
            case .text, .markdown:
                try viewModel.transcript.write(to: url, atomically: true, encoding: .utf8)
            case .docx:
                try DocxExporter.export(text: viewModel.transcript, to: url)
            }
        } catch {
            showExportError = true
        }
    }
}

#Preview {
    ContentView()
}
