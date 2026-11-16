import SwiftUI

enum HexColor {
    /// Parses `#rgb`, `#rrggbb` or `#rrggbbaa` (leading `#` optional). Invalid input is nil.
    static func parse(_ text: String?) -> Color? {
        guard var hex = text?.trimmingCharacters(in: .whitespaces), !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.allSatisfy(\.isHexDigit) else { return nil }
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let hasAlpha = hex.count == 8
        let shift: UInt64 = hasAlpha ? 8 : 0
        let r = Double((value >> (16 + shift)) & 0xFF) / 255
        let g = Double((value >> (8 + shift)) & 0xFF) / 255
        let b = Double((value >> shift) & 0xFF) / 255
        let a = hasAlpha ? Double(value & 0xFF) / 255 : 1
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

struct AccountLabelView: View {
    let label: String
    let style: AccountLabelStyle
    let color: String?
    let mutedColor: String

    private static let darkInk = Color(red: 0.11, green: 0.11, blue: 0.12)

    var body: some View {
        switch style {
        case .badge:
            Text("[\(label)]")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Self.darkInk)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 3).fill(HexColor.parse(color) ?? Color.gray.opacity(0.6))
                )
        case .solo:
            Text("solo·\(label)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(HexColor.parse(mutedColor) ?? Color.secondary)
                .lineLimit(1)
        }
    }
}
