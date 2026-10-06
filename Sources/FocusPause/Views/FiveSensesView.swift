import SwiftUI

/// 五感着陆：先看一页清单，再进入分步引导（5 看 → 4 触 → 3 听 → 2 闻 → 1 尝）。
struct FiveSensesView: View {
    @ObservedObject var state: AppState
    @State private var started = false
    @State private var step = 0

    private let steps: [(count: Int, icon: String, prompt: String)] = [
        (5, "eye", "环顾四周，说出 5 件你能看到的东西。"),
        (4, "hand.tap", "感受 4 种触感，摸摸身边熟悉的物件。"),
        (3, "ear", "停下来，留意 3 个你能听到的声音。"),
        (2, "nose", "仔细闻一闻，发现 2 种气味。"),
        (1, "mouth", "留意口腔里 1 种味道或感受。"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if started {
                    stepsView
                } else {
                    checklistView
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    // MARK: - 清单

    private var checklistView: some View {
        VStack(spacing: 16) {
            Text("把注意力从脑海里，拉回到当下真实的五种感受。按顺序完成每一步。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.top, 6)

            Link(destination: URL(string: "https://ebp.gesedna.com/pa-toolbox-emo-fivesense-nominate-read/?rd=%2Fpa-emotion-cool-down%2F%2F%3Frd%3D%2Fpa-pause-tool")!) {
                Label("去暂停实验室五感着陆", systemImage: "arrow.up.right.square")
                    .font(.subheadline)
            }
            .foregroundStyle(Color.focusAccent)

            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(item.prompt)
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(.vertical, 13)
                    .padding(.horizontal, 14)
                    .overlay(alignment: .bottom) {
                        if index < steps.count - 1 {
                            Rectangle().fill(Color.surfaceDivider).frame(height: 1)
                        }
                    }
                }
            }
            .focusList()

            Button {
                step = 0
                started = true
            } label: {
                Label("开始分步引导", systemImage: "play.fill")
            }
            .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
        }
        .padding()
    }

    // MARK: - 分步

    private var stepsView: some View {
        let current = steps[step]
        return VStack(spacing: 20) {
            HStack {
                Button {
                    started = false
                } label: {
                    Label("退出", systemImage: "xmark")
                }
                .buttonStyle(AlwaysActiveBorderlessStyle())
                Spacer()
            }

            Image(systemName: current.icon)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)

            Text("\(current.count)")
                .font(.system(size: 120, weight: .light))
                .foregroundStyle(Color.focusAccent)
                .monospacedDigit()

            Text(current.prompt)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // 进度点
            HStack(spacing: 10) {
                ForEach(0..<steps.count, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.focusAccent : Color.secondary.opacity(0.25))
                        .frame(width: 8, height: 8)
                }
            }

            Button {
                if step < steps.count - 1 {
                    step += 1
                } else {
                    started = false
                    step = 0
                }
            } label: {
                Label(step < steps.count - 1 ? "下一步" : "完成", systemImage: "checkmark")
            }
            .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
