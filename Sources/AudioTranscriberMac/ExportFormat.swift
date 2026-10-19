import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case text = "Text"
    case markdown = "Markdown"
    case docx = "Word"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .text: "txt"
        case .markdown: "md"
        case .docx: "docx"
        }
    }

    var contentType: UTType {
        switch self {
        case .text: .plainText
        case .markdown: UTType(filenameExtension: "md") ?? .plainText
        case .docx: UTType(filenameExtension: "docx") ?? .data
        }
    }
}
