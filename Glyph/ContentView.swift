import SwiftUI

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument

    var body: some View {
        EditorWebView(document: document)
            .frame(minWidth: 480, minHeight: 320)
            .ignoresSafeArea()
    }
}
