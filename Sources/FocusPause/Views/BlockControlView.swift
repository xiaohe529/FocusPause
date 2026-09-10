import SwiftUI

/// 「屏蔽」标签页：把网站屏蔽 / App屏蔽 / 网络控制三个子页合并成一个入口，
/// 内部用系统分段控件切换（与一级标签区分层级）。
struct BlockControlView: View {
    @ObservedObject var state: AppState
    @State private var blockMode = 0

    var body: some View {
        VStack(spacing: 0) {
            SetupChecklistView(state: state)
                .padding(.bottom, 12)

            SubSegmentCard(
                options: [
                    .init(value: 0, label: "网站屏蔽", icon: "globe"),
                    .init(value: 1, label: "App屏蔽", icon: "xmark.app"),
                    .init(value: 2, label: "网络控制", icon: "network.slash"),
                ],
                selection: $blockMode
            )
            .padding(.bottom, 12)

            Group {
                switch blockMode {
                case 1: AppListView(state: state)
                case 2: WiFiView(state: state)
                default: WebsiteListView(state: state)
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}