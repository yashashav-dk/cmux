import Foundation
import Testing
@testable import CmuxClaudeLimits

struct PanelStringsCatalogTests {
    private func catalog() throws -> [String: [String: String]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CmuxClaudeLimits/Resources/Localizable.xcstrings")
        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: [String: Any]])
        var result: [String: [String: String]] = [:]
        for (key, entry) in strings {
            let locs = try #require(entry["localizations"] as? [String: [String: Any]])
            result[key] = locs.compactMapValues { ($0["stringUnit"] as? [String: Any])?["value"] as? String }
        }
        return result
    }

    @Test func everyLocaleKeepsEnglishPlaceholders() throws {
        let catalog = try catalog()
        #expect(!catalog.isEmpty)
        for (key, values) in catalog {
            let english = try #require(values["en"], "\(key) missing en")
            #expect(values.count == 9, "\(key) must carry all nine locales")
            for (locale, value) in values {
                #expect(
                    PanelStrings.placeholderCount(value) == PanelStrings.placeholderCount(english),
                    "\(key) [\(locale)] placeholder count differs from English"
                )
            }
        }
    }

    @Test func mismatchedTranslationFallsBackToEnglish() {
        #expect(PanelStrings.safeFormat("in", fallback: "in %@") == "in %@")
        #expect(PanelStrings.safeFormat("%@ %@", fallback: "in %@") == "in %@")
        #expect(PanelStrings.safeFormat("noch %@", fallback: "in %@") == "noch %@")
        #expect(PanelStrings.safeFormat("%2$@ %1$@ %3$@", fallback: "%@ %@ %@") == "%2$@ %1$@ %3$@")
    }
}
