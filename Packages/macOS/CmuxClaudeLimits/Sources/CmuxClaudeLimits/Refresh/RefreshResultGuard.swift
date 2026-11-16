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

    /// The result object is the last JSON object in stdout that parses and has `num_turns`.
    /// Each `{` is tried as a start (from the end), so junk anywhere cannot hide it.
    private static func lastTopLevelObject(in data: Data) -> [String: Any]? {
        let bytes = [UInt8](data)
        for start in bytes.indices.reversed() where bytes[start] == 0x7B {
            guard let end = balancedEnd(in: bytes, from: start) else { continue }
            let slice = Data(bytes[start...end])
            if let object = (try? JSONSerialization.jsonObject(with: slice)) as? [String: Any],
               object["num_turns"] != nil {
                return object
            }
        }
        return nil
    }

    private static func balancedEnd(in bytes: [UInt8], from start: Int) -> Int? {
        var depth = 0
        var inString = false
        var escaped = false
        for i in start..<bytes.count {
            let byte = bytes[i]
            if inString {
                if escaped { escaped = false } else if byte == 0x5C { escaped = true } else if byte == 0x22 { inString = false }
                continue
            }
            switch byte {
            case 0x22: inString = true
            case 0x7B: depth += 1
            case 0x7D:
                depth -= 1
                if depth == 0 { return i }
            default: break
            }
        }
        return nil
    }
}
