import SwiftUI

/// 「暂停一下」标签页：正念呼吸 / 五感着陆 / 一些提示 三个子入口，二级分段切换。
struct PauseView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            SubSegmentCard(
                options: [
                    .init(value: AppState.PauseMode.breathing, label: "我的工具箱", icon: "wrench.and.screwdriver"),
                    .init(value: AppState.PauseMode.grounding, label: "五感着陆", icon: "5.circle"),
                    .init(value: AppState.PauseMode.cards, label: "一些提示", icon: "quote.bubble"),
                ],
                selection: $state.pauseMode
            )
            .padding(.bottom, 12)

            switch state.pauseMode {
            case .breathing: BreathingView(state: state)
            case .grounding: FiveSensesView(state: state)
            case .cards: HintsView(state: state)
            }
        }
    }
}