import Foundation

/// Injected into every admin page on iPhone so portrait works even when the server
/// has not been redeployed with `admin-portrait-ok` CSS/JS changes.
/// Source: lib/ios-admin-portrait-scripts.js (sync via scripts/sync-ios-portrait-resources.js)
enum PortraitWebScripts {
    static let documentStart: String = loadScript(named: "portrait-document-start")
    static let applyAfterLoad: String = loadScript(named: "portrait-apply-after-load")

    private static func loadScript(named name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            fatalError("Missing portrait script \(name).js — run: node scripts/sync-ios-portrait-resources.js")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
