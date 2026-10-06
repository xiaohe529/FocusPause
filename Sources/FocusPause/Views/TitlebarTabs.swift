import SwiftUI

/// 标题栏：只保留应用名（靠左，紧接红绿灯）和设置齿轮（靠右）。
/// 一级导航已经下移到窗口内容区（见 `MainView.primaryTabs`）。
/// 由 `SettingsWindowController` 用 `NSTitlebarAccessoryViewController` 装进标题栏，
/// 所以它天然和红绿灯对齐、高度也一致，不会把窗口内容往下推。
struct TitlebarTabsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            Text("Focus&Pause")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
                .padding(.leading, 2)

            Spacer(minLength: 0)

            settingsButton
                .padding(.trailing, 12)
        }
        .padding(.leading, 78)   // 让开红绿灯
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 设置齿轮：点击后在主窗口内打开设置页（不再另起窗口）。
    private var settingsButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { state.selectedTab = 3 }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13))
                .foregroundStyle(state.selectedTab == 3 ? Color.focusAccent : Color.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("设置")
    }
}
