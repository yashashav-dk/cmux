import Foundation
import Testing
#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("Fork build policy")
struct ForkBuildTests {
    @Test func forkPolicyDisablesUpdater() {
        #expect(ForkBuildPolicy.isUpdaterDisabled())
    }

    @Test func forkMenuTitleNamesSync() {
        #expect(ForkBuildPolicy.updatesMenuTitle.contains("scripts/fork/sync.sh"))
    }
}
