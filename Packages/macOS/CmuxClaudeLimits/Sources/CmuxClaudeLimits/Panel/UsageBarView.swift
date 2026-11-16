import SwiftUI

struct UsageBarView: View {
    let percent: Double
    let tone: BarTone

    static func color(for tone: BarTone) -> Color {
        switch tone {
        case .normal: return Color.accentColor
        case .warning: return Color(red: 0.90, green: 0.68, blue: 0.10)
        case .critical: return Color(red: 0.88, green: 0.22, blue: 0.20)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let fraction = percent.isFinite ? min(1, max(0, percent / 100)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                if fraction > 0 {
                    Capsule()
                        .fill(Self.color(for: tone))
                        .frame(width: max(3, proxy.size.width * fraction))
                }
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}
