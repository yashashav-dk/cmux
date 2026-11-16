import CmuxFoundation
import Foundation
import Testing

@Suite struct ClaudeLimitsSchemaTests {
    private func issues(_ claudeLimits: [String: Any]) -> [CmuxConfigSemanticIssue] {
        CmuxConfigSemanticValidator(scope: .global).validate(
            jsonObject: ["schemaVersion": 1, "claudeLimits": claudeLimits]
        )
    }

    private func sample() -> [String: Any] {
        ClaudeLimitsSettingsKeyTests.sample
    }

    @Test func acceptsDocumentedShape() {
        #expect(issues(sample()).isEmpty)
    }

    @Test func rejectsRefreshIntervalBelowSixty() {
        var object = sample()
        object["refreshIntervalSeconds"] = 30
        let found = issues(object)
        #expect(found.count == 1)
        #expect(found.first?.path.contains("claudeLimits.refreshIntervalSeconds") == true)
    }

    @Test func rejectsUnknownStyle() {
        var object = sample()
        object["accounts"] = [["label": "a", "style": "pill"]]
        #expect(issues(object).count == 1)
    }

    @Test func rejectsUnknownAccountKey() {
        var object = sample()
        object["accounts"] = [["label": "a", "email": "x@example.com"]]
        #expect(issues(object).count == 1)
    }
}
