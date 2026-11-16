import Foundation
import Testing
@testable import CmuxClaudeLimits

struct RefreshResultGuardTests {
    private func verdict(_ text: String) -> GuardVerdict {
        RefreshResultGuard().evaluate(stdout: Data(text.utf8))
    }

    @Test func zeroTurnsZeroCostIsClean() {
        #expect(verdict(#"{"is_error":false,"num_turns":0,"total_cost_usd":0,"result":"x"}"#) == .clean)
    }

    @Test func turnsTrip() {
        #expect(verdict(#"{"is_error":false,"num_turns":1,"total_cost_usd":0}"#) == .tripped("num_turns=1"))
    }

    @Test func costTrips() {
        #expect(verdict(#"{"is_error":false,"num_turns":0,"total_cost_usd":0.003}"#) == .tripped("total_cost_usd=0.003"))
    }

    @Test func isErrorTrips() {
        #expect(verdict(#"{"is_error":true,"num_turns":0,"total_cost_usd":0}"#) == .tripped("is_error"))
    }

    @Test func noisyOutputUsesLastObject() {
        let text = "hook: warming up\n{\"is_error\":false,\"num_turns\":0,\"total_cost_usd\":0}\nhook done\n"
        #expect(verdict(text) == .clean)
    }

    @Test func bracesInsideStringsAreIgnored() {
        #expect(verdict(#"{"result":"a } { b","num_turns":0,"total_cost_usd":0}"#) == .clean)
    }

    @Test func garbageIsUnparseable() {
        #expect(verdict("node: command not found") == .unparseable)
    }
}
