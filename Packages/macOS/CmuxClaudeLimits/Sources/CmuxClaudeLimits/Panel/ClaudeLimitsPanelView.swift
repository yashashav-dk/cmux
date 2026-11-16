public import SwiftUI

public struct ClaudeLimitsPanelView: View {
    private let model: ClaudeLimitsPanelModel
    private let actions: any PanelActions

    public init(model: ClaudeLimitsPanelModel, actions: any PanelActions) {
        self.model = model
        self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !model.isCollapsed {
                if model.needsScroll {
                    ScrollView { cardList }.scrollIndicators(.hidden)
                } else {
                    cardList
                }
            }
        }
        .padding(.vertical, PanelLayoutMetrics.verticalPadding)
        .padding(.horizontal, 10)
        .frame(height: model.reservedHeight, alignment: .top)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ClaudeLimitsPanel")
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                model.refreshPresentation()
            }
        }
    }

    private var cardList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.cards) { card in
                AccountCardView(card: card, mutedColor: model.configuration.mutedColor)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(PanelStrings.header)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button {
                Task { await actions.refreshNow() }
            } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(PanelStrings.refresh)
            .accessibilityLabel(PanelStrings.refresh)
            .accessibilityIdentifier("ClaudeLimitsRefreshButton")
            if let age = model.refreshAgeText {
                Text(age)
                    .font(.system(size: 10, design: .monospaced).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button {
                let collapsed = !model.isCollapsed
                model.isCollapsed = collapsed
                actions.setCollapsed(collapsed)
            } label: {
                Image(systemName: model.isCollapsed ? "chevron.right" : "chevron.down").font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(model.isCollapsed ? PanelStrings.expand : PanelStrings.collapse)
            .accessibilityLabel(model.isCollapsed ? PanelStrings.expand : PanelStrings.collapse)
            .accessibilityIdentifier("ClaudeLimitsCollapseButton")
        }
        .frame(height: PanelLayoutMetrics.headerHeight)
    }
}
