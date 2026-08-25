import SwiftUI
import AppKit

/// 自绘提醒弹窗面板（取代系统 NSAlert），分为三个版块：
/// 1) 专注计时/延时屏蔽（文案提示、预设时间、自定义时间、事件）
/// 2) 暂停一下（唯一跳转到「暂停一下」版块的按钮）
/// 3) 提示去做（每个提示单独一行，仅展示、不可点）
/// 面板是 AppKit 模态（`NSApp.runModal(for:)`），SwiftUI 按钮写入结果后关闭。

enum PanelChoice {
    case primary          // 主按钮（立即开启 / 开始）
    case preset(Int)      // 选中的预设时长（分钟）
    case custom(Int)      // 自定义分钟
    case pause            // 点了「暂停一下」，跳转到暂停版块
    case secondary        // 次按钮（稍后提醒 / 取消）
    case tertiary         // 第三按钮（不再提醒 / 本次算了）
    case cancel           // 关闭
}

final class PanelResult {
    var choice: PanelChoice = .cancel
    var goal = ""
}

struct PromptPanelConfig {
    var title: String
    var icon: String
    var section1Title: String
    var message: String
    var presets: [(String, Int)] = []
    var showGoal = false
    var goalPlaceholder: String? = nil
    var actionItems: [PromptItem] = []
    var textItems: [PromptItem] = []
    var primaryTitle = "确定"
    var secondaryTitle: String? = nil
    var tertiaryTitle: String? = nil
}

struct PracticePromptPanel: View {
    let config: PromptPanelConfig
    let result: PanelResult
    let dismiss: () -> Void
    @State private var duration: DurationSel
    @State private var goal = ""
    @State private var toast: String?
    @State private var toastGeneration = 0
    @State private var textHintIndex = 0

    private enum DurationSel {
        case preset(Int)
        case custom(Int)
    }

    private let toastPool = ["去吧，记得回来哦", "休息一下，马上回来", "去做吧，慢慢来", "记得照顾好自己"]

    init(config: PromptPanelConfig, result: PanelResult, dismiss: @escaping () -> Void) {
        self.config = config
        self.result = result
        self.dismiss = dismiss
        _duration = State(initialValue: config.presets.first.map { .preset($0.1) } ?? .custom(30))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            section1
            pauseSection
            if !config.actionItems.isEmpty {
                hintsSection
            }
            if !config.textItems.isEmpty {
                textHintSection
            }
            footer
        }
        .padding(16)
        .frame(width: 380, alignment: .top)
        .onAppear { pickRandomTextHint(forceDifferent: false) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: config.icon)
                .font(.system(size: 24))
                .foregroundStyle(Color.focusAccent)
            Text(config.title)
                .font(.title3.weight(.semibold))
        }
    }

    // MARK: - 版块 1：专注计时 / 延时屏蔽

    private var section1: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(config.section1Title)
                .font(.headline)
            Text(config.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !config.presets.isEmpty {
                Text("预设时间")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(config.presets, id: \.1) { preset in
                        Button {
                            duration = .preset(preset.1)
                        } label: {
                            Text(preset.0)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(AlwaysActiveButtonStyle(
                            color: selectedPreset == preset.1 ? .focusActive : .gray))
                    }
                }

                HStack {
                    Text("自定义时间")
                        .font(.subheadline)
                    Spacer()
                    TextField("", value: customBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 52)
                    Text("分钟")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if config.showGoal {
                TextField(config.goalPlaceholder ?? "", text: $goal, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
            }

            // 主按钮（开始 / 立即开启）放在本版块，包内容、居中
            HStack {
                Spacer()
                Button {
                    result.goal = goal
                    result.choice = primaryChoice
                    dismiss()
                } label: {
                    Text(config.primaryTitle)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
                Spacer()
            }
        }
        .focusCard()
    }

    // MARK: - 版块 2：暂停一下

    private var pauseSection: some View {
        HStack {
            Spacer()
            Button {
                result.choice = .pause
                dismiss()
            } label: {
                Label("暂停一下", systemImage: "pause.circle.fill")
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(AlwaysActiveButtonStyle(color: .focusActive))
            Spacer()
        }
    }

    // MARK: - 版块 3：提示去做

    private var hintsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("一些提醒")
                .font(.headline)
            FlowLayout(spacing: 6) {
                ForEach(config.actionItems) { item in
                    Button {
                        showToast()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "hand.point.right")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.focusAccent)
                            Text(item.text)
                                .font(.body)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            if let toast {
                Text(toast)
                    .font(.caption)
                    .foregroundStyle(Color.focusAccent)
                    .transition(.opacity)
            }
        }
        .focusCard()
    }

    // MARK: - 底部文字提示（随机一句，可点击换下一句）

    private var textHintSection: some View {
        Button {
            pickRandomTextHint(forceDifferent: true)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "quote.opening")
                    .foregroundStyle(Color.focusAccent)
                Text("「\(config.textItems[textHintIndex].text)」")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: "shuffle")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
            .font(.body)
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("换一句")
    }

    private func showToast() {
        let message = toastPool.randomElement() ?? "去吧，记得回来哦"
        toastGeneration += 1
        let generation = toastGeneration
        withAnimation(.easeOut(duration: 0.15)) { toast = message }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            // 只有最新一次点击的 Task 才清除，避免连点导致旧 Task 提前清掉新提示
            guard toastGeneration == generation else { return }
            withAnimation(.easeIn(duration: 0.2)) { toast = nil }
        }
    }

    private func pickRandomTextHint(forceDifferent: Bool) {
        let count = config.textItems.count
        guard count > 0 else { return }
        if count == 1 || !forceDifferent {
            textHintIndex = Int.random(in: 0..<count)
        } else {
            var next = textHintIndex
            while next == textHintIndex { next = Int.random(in: 0..<count) }
            textHintIndex = next
        }
    }

    // MARK: - 底部按钮

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            if let tertiaryTitle = config.tertiaryTitle {
                Button(tertiaryTitle) {
                    result.choice = .tertiary
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if let secondaryTitle = config.secondaryTitle {
                Button(secondaryTitle) {
                    result.choice = .secondary
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Spacer()
        }
    }

    private var selectedPreset: Int? {
        if case .preset(let minutes) = duration { return minutes }
        return nil
    }

    /// 数字框显示当前选中的时长（预设或自定义都跟随），输入即切换为自定义。
    private var customMinutes: Int {
        switch duration {
        case .preset(let minutes): return minutes
        case .custom(let minutes): return minutes
        }
    }

    private var customBinding: Binding<Int> {
        Binding(
            get: { customMinutes },
            set: { duration = .custom($0) }
        )
    }

    private var primaryChoice: PanelChoice {
        guard !config.presets.isEmpty else { return .primary }
        if case .preset(let minutes) = duration { return .preset(minutes) }
        return .custom(customMinutes)
    }
}

/// AppKit 层：把 `PracticePromptPanel` 包进 `NSPanel`，以模态方式运行，返回选择结果。
@MainActor
enum PromptPanelPresenter {
    static func run(_ config: PromptPanelConfig) -> PanelResult {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.titled, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.hidesOnDeactivate = false

        let result = PanelResult()
        let dismiss: () -> Void = {
            panel.orderOut(nil)
            NSApp.stopModal()
        }
        let root = PracticePromptPanel(config: config, result: result, dismiss: dismiss)
        let controller = NSHostingController(rootView: root)
        panel.contentViewController = controller
        let size = controller.view.fittingSize
        panel.setContentSize(NSSize(width: max(380, min(size.width, 480)), height: max(220, size.height)))

        // 手动居中于主屏幕：窗口尚未上屏时 center() 可能失效，导致面板落在屏幕上方。
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = panel.frame
            let origin = NSPoint(
                x: screen.visibleFrame.midX - frame.width / 2,
                y: screen.visibleFrame.midY - frame.height / 2
            )
            panel.setFrameOrigin(origin)
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: panel)
        return result
    }
}