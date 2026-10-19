import Foundation

enum DocxExportError: Error {
    case zipFailed(Int32)
}

/// Swift has no equivalent of python-docx. A .docx file is just a ZIP
/// archive of a small set of OOXML (WordprocessingML) XML files -- this
/// builds the minimal valid set by hand (one paragraph per line, no rich
/// formatting) and shells out to the system's /usr/bin/zip to produce the
/// archive, rather than adding a new SPM dependency just for ZIP writing.
/// /usr/bin/zip ships with macOS itself (not just Xcode Command Line
/// Tools), so this has no extra toolchain requirement beyond what's
/// already needed to run the app at all.
enum DocxExporter {
    static func export(text: String, to destinationURL: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let wordDir = tempDir.appendingPathComponent("word", isDirectory: true)
        let relsDir = tempDir.appendingPathComponent("_rels", isDirectory: true)

        try FileManager.default.createDirectory(at: wordDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try contentTypesXML.write(
            to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8
        )
        try rootRelsXML.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)
        try documentXML(for: text).write(
            to: wordDir.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8
        )

        // NSSavePanel already confirmed overwrite with the user before
        // handing us this URL; zip would otherwise *update* an existing
        // archive rather than replace it, which could leave stray entries
        // if something else happened to exist at this path.
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = tempDir
        // -X: strip extra file attributes (resource forks/Finder info) --
        // irrelevant to a document archive and not something a strict OPC
        // reader should ever see.
        process.arguments = ["-r", "-X", destinationURL.path, "."]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DocxExportError.zipFailed(process.terminationStatus)
        }
    }

    private static let contentTypesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """

    private static let rootRelsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """

    private static func documentXML(for text: String) -> String {
        let paragraphs = text
            .components(separatedBy: "\n")
            .map { "<w:p><w:r><w:t xml:space=\"preserve\">\(escapeXML($0))</w:t></w:r></w:p>" }
            .joined()

        return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
            <w:body>
            \(paragraphs)
            <w:sectPr/>
            </w:body>
            </w:document>
            """
    }

    // Order matters: '&' must be escaped first, or the entities below
    // (which themselves contain '&') would get double-escaped.
    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
