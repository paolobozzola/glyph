import SwiftUI

@main
struct GlyphApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { configuration in
            ContentView(document: configuration.document)
        }
    }
}
