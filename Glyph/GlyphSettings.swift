import AppKit
import WebKit

/// Preferences model, **shared** between the main app and the sandboxed Quick Look preview
/// extension via an App Group. Both targets compile this file. The app writes prefs (from the
/// Settings window) into the group suite; the QL extension reads them so a preview renders with
/// the user's exact typography — identical to the editor. See docs/POLISH.md.
enum GlyphSettings {
    static let appGroup = "group.com.paolobozzola.glyph"
    /// App Group suite so app ⇄ QL extension share values. Falls back to `.standard` when the
    /// group is unavailable (e.g. an unsigned local build) so the app still works.
    static let defaults: UserDefaults = UserDefaults(suiteName: appGroup) ?? .standard

    static let didChange = Notification.Name("glyph.settingsChanged")

    // Editing
    static let dimKey = "glyph.dim"
    static let anchorKey = "glyph.twAnchor"
    static let cadenceKey = "glyph.twCadence"
    static let rememberKey = "glyph.rememberModes"
    static let lastDimKey = "glyph.lastDim"
    static let lastTypewriterKey = "glyph.lastTypewriter"
    // Typography — relative scale: Body = 1rem = base px; headings are rem multiples.
    static let bodyPxKey = "glyph.bodyPx"
    static let headingKeys = ["glyph.h1", "glyph.h2", "glyph.h3", "glyph.h4", "glyph.h5", "glyph.h6"]
    static let headingFontKey = "glyph.fontHeading"
    static let bodyFontKey = "glyph.fontBody"
    static let codeFontKey = "glyph.fontCode"

    static let dimChoices: [Double] = [0.6, 0.45, 0.3]
    static let anchorChoices: [Double] = [0.38, 0.45, 0.50]
    static let bodyChoices: [Double] = [14, 15, 16, 17, 18]
    static let headingDefaults: [Double] = [2.75, 2.0, 1.5, 1.25, 1.125, 1.0]  // H1…H6
    static let headingFontChoices = ["New York", "Charter", "Iowan Old Style", "Georgia", "System", "Helvetica Neue"]
    static let bodyFontChoices = ["System", "New York", "Charter", "Iowan Old Style", "Georgia", "Helvetica Neue", "SF Mono", "Menlo"]
    static let codeFontChoices = ["SF Mono", "Menlo", "Monaco"]

    static var dim: Double { defaults.object(forKey: dimKey) as? Double ?? 0.45 }
    static var anchor: Double { defaults.object(forKey: anchorKey) as? Double ?? 0.45 }
    static var cadence: String { defaults.string(forKey: cadenceKey) ?? "line" }
    static var remember: Bool { defaults.bool(forKey: rememberKey) }
    static var bodyPx: Double { defaults.object(forKey: bodyPxKey) as? Double ?? 16 }
    static func headingRem(_ i: Int) -> Double { defaults.object(forKey: headingKeys[i]) as? Double ?? headingDefaults[i] }
    static var headingFont: String { defaults.string(forKey: headingFontKey) ?? "New York" }
    static var bodyFont: String { defaults.string(forKey: bodyFontKey) ?? "System" }
    static var codeFont: String { defaults.string(forKey: codeFontKey) ?? "SF Mono" }

    /// The JS payload for `applySettings` — used by the editor and the Quick Look preview.
    static var applySettingsJSON: String {
        let hs = (0..<6).map { String(headingRem($0)) }.joined(separator: ",")
        return "{dim:\(dim),twAnchor:\(anchor),twCadence:'\(cadence)',bodyPx:\(bodyPx)," +
               "headings:[\(hs)],fonts:{heading:'\(headingFont)',body:'\(bodyFont)',code:'\(codeFont)'}}"
    }

    static func pushValues(to webView: WKWebView) {
        webView.evaluateJavaScript("window.glyph && window.glyph.applySettings(\(applySettingsJSON))")
    }

    static func apply(to webView: WKWebView, restoringModes: Bool) {
        pushValues(to: webView)
        if restoringModes && remember {
            let d = defaults.bool(forKey: lastDimKey)
            let t = defaults.bool(forKey: lastTypewriterKey)
            webView.evaluateJavaScript("window.glyph && window.glyph.restoreModes({dim:\(d),typewriter:\(t)})")
        }
    }

    static func notifyChanged() { NotificationCenter.default.post(name: didChange, object: nil) }

    /// Approximate a friendly font name with a native NSFont (for the Settings preview).
    static func nsFont(_ name: String, size: CGFloat, bold: Bool) -> NSFont {
        switch name {
        case "New York":
            let sys = NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
            if let d = sys.fontDescriptor.withDesign(.serif) { return NSFont(descriptor: d, size: size) ?? sys }
            return sys
        case "System":
            return NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        case "SF Mono":
            return NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
        default:
            let base = NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
            return bold ? NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask) : base
        }
    }
}
