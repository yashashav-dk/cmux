public import CoreGraphics

public enum PanelLayoutMetrics {
    public static let headerHeight: CGFloat = 22
    public static let cardLabelHeight: CGFloat = 16
    public static let rowHeight: CGFloat = 16
    public static let cardSpacing: CGFloat = 4
    public static let verticalPadding: CGFloat = 6
    public static let maxHeight: CGFloat = 280

    public static func reservedHeight(accountCount: Int, visibleRows: Int, enabled: Bool, expanded: Bool) -> CGFloat {
        guard enabled, accountCount > 0 else { return 0 }
        let base = headerHeight + 2 * verticalPadding
        guard expanded else { return base }
        let cards = CGFloat(accountCount) * (cardLabelHeight + cardSpacing)
        let rows = CGFloat(max(0, visibleRows)) * rowHeight
        return min(maxHeight, base + cards + rows)
    }
}
