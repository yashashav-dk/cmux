import SwiftUI

struct AccountCardView: View {
    let card: AccountCard
    let mutedColor: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                AccountLabelView(label: card.label, style: card.style, color: card.color, mutedColor: mutedColor)
                if let status = card.statusText {
                    Text(status)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(card.statusTooltip ?? "")
                }
                Spacer(minLength: 0)
            }
            .frame(height: PanelLayoutMetrics.cardLabelHeight)
            ForEach(card.rows) { row in
                UsageRowView(row: row)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("ClaudeLimitsRow.\(card.id).\(row.id)")
            }
        }
        .padding(.bottom, PanelLayoutMetrics.cardSpacing)
        .opacity(card.isDimmed ? 0.55 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ClaudeLimitsCard.\(card.id)")
    }
}

struct UsageRowView: View {
    let row: RowPresentation

    var body: some View {
        HStack(spacing: 5) {
            Text(row.title)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 22, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            UsageBarView(percent: row.percent, tone: row.tone)
                .frame(minWidth: 40)
            Text("\(Int(row.percent.rounded()))%")
                .font(.system(size: 10, design: .monospaced).monospacedDigit())
                .frame(width: 30, alignment: .trailing)
            Text(row.resetText)
                .font(.system(size: 10, design: .monospaced).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 66, alignment: .leading)
        }
        .frame(height: PanelLayoutMetrics.rowHeight)
        .help(row.tooltip)
    }
}
