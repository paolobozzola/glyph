import AppKit

// Programmatic entry point (no storyboard / MainMenu.xib). The AppDelegate builds
// the main menu and the rest of the document-based app wiring.
let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
