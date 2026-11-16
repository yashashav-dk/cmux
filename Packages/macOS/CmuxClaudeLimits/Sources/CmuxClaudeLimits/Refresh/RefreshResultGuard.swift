public import Foundation

/// Parses the CLI's JSON result and trips if it ever reports inference.
public struct RefreshResultGuard: Sendable {
    public init() {}

    public func evaluate(stdout: Data) -> GuardVerdict {
        guard let object = Self.lastTopLevelObject(in: stdout) else { return .unparseable }
        if (object["is_error"] as? Bool) == true { return .tripped("is_error") }
        if let turns = (object["num_turns"] as? NSNumber)?.doubleValue, turns > 0 {
            return .tripped("num_turns=\(Int(turns))")
        }
        if let cost = (object["total_cost_usd"] as? NSNumber)?.doubleValue, cost > 0 {
            return .tripped("total_cost_usd=\(cost)")
        }
        return .clean
    }

    private static func lastTopLevelObject(in data: Data) -> [String: Any]? {
        let bytes = [UInt8](data)
        var ranges: [Range<Int>] = []
        var depth = 0
        var start = 0
        var inString = false
        var escaped = false
        for (i, byte) in bytes.enumerated() {
            if inString {
                if escaped { escaped = false } else if byte == 0x5C { escaped = true } else if byte == 0x22 { inString = false }
                continue
            }
            switch byte {
            case 0x22 where depth > 0: inString = true
            case 0x7B:
                if depth == 0 { start = i }
                depth += 1
            case 0x7D where depth > 0:
                depth -= 1
                if depth == 0 { ranges.append(start..<(i + 1)) }
            default: break
            }
        }
        for range in ranges.reversed() {
            let slice = Data(bytes[range])
            if let object = (try? JSONSerialization.jsonObject(with: slice)) as? [String: Any] { return object }
        }
        return nil
    }
}
