import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// De-facto Markdown UTI, imported in Info.plist (see docs/SHELL.md §5).
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
}

/// The Markdown text *is* the document — the single source of truth.
/// `ReferenceFileDocument` (a class) suits an editor with a long-lived WKWebView,
/// and its snapshot/write give autosave-in-place + Versions in later milestones.
final class MarkdownDocument: ReferenceFileDocument {
    typealias Snapshot = String

    static var readableContentTypes: [UTType] { [.markdown, .plainText] }
    static var writableContentTypes: [UTType] { [.markdown] }

    @Published var text: String

    init(text: String = "# New Document\n\nStart writing…\n") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = string
    }

    func snapshot(contentType: UTType) throws -> String { text }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }
}
