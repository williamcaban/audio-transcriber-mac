enum ContentTab: String, CaseIterable, Identifiable {
    case transcript = "Transcript"
    case report = "Report & Summary"
    case translation = "Translation"

    var id: String { rawValue }
}
