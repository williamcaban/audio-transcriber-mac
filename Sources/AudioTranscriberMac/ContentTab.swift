enum ContentTab: String, CaseIterable, Identifiable {
    case transcript = "Transcript"
    case report = "Report & Summary"

    var id: String { rawValue }
}
