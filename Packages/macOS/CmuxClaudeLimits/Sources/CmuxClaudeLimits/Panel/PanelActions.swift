public protocol PanelActions: Sendable {
    func refreshNow() async
    func setCollapsed(_ collapsed: Bool)
}
