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
    case elapsed          // 选「正计时」（不限时）
    case pause            // 点了「暂停一下」，跳转到暂停版块
    case secondary        // footer 次按钮（取消）
    case tertiary         // footer 第三按钮（稍后提醒）
    case sectionAction    // 版块内的第二个动作（如「立即屏蔽」）
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
    /// 「倒计时 / 正计时」模式切换（显示在版块顶部）。开启后正计时隐藏时长、主按钮文案用 elapsedPrimaryTitle。
    var showModePicker = false
    /// 正计时时主按钮文案（默认「开始正计时」）。
    var elapsedPrimaryTitle: String? = nil
    /// 版块内主按钮下方的第二个动作（如「立即屏蔽」），返回 .sectionAction。描边风格以示区别于「暂停一下」。
    var sectionActionTitle: String? = nil
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
    @State private var elapsedMode = false
    @FocusState private var goalFocused: Bool
    @FocusState private var minutesFocused: Bool

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
        .onAppear {
            pickRandomTextHint(forceDifferent: false)
            // 有事件输入框时自动聚焦，打开就能看见光标、直接输入，避免「点不到/没光标」。
            if config.showGoal {
                DispatchQueue.main.async { goalFocused = true }
            }
        }
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

            // 「倒计时 / 正计时」模式切换（与主页面一致）；正计时隐藏时长、事件输入仍共用。
            if config.showModePicker {
                Picker("模式", selection: $elapsedMode) {
                    Text("倒计时").tag(false)
                    Text("正计时").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }

            if config.showModePicker && elapsedMode {
                VStack(alignment: .leading, spacing: 4) {
                    Text("不限时专注")
                        .font(.subheadline.weight(.semibold))
                    Text("向下累计时长，自己决定何时结束；结束时需密码，不占用紧急退出次数。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !config.presets.isEmpty {
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
                        .focused($minutesFocused)
                    Text("分钟")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if config.showGoal {
                TextField(config.goalPlaceholder ?? "", text: $goal, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .focused($goalFocused)
            }

            // 主按钮（开始 / 立即开启 / 开始正计时）放在本版块，包内容、居中
            HStack {
                Spacer()
                Button {
                    result.goal = goal
                    result.choice = primaryChoice
                    dismiss()
                } label: {
                    Text(primaryButtonTitle)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
                Spacer()
            }

            // 版块内第二个动作（如「立即屏蔽」），返回 .sectionAction——描边样式，与「暂停一下」区分。
            if let sectionActionTitle = config.sectionActionTitle {
                HStack {
                    Spacer()
                    Button {
                        result.goal = goal
                        result.choice = .sectionAction
                        dismiss()
                    } label: {
                        Text(sectionActionTitle)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.focusActive)
                    Spacer()
                }
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
        if config.showModePicker && elapsedMode { return .elapsed }
        guard !config.presets.isEmpty else { return .primary }
        if case .preset(let minutes) = duration { return .preset(minutes) }
        return .custom(customMinutes)
    }

    /// 主按钮文案：正计时模式用「开始正计时」，否则用 config.primaryTitle。
    private var primaryButtonTitle: String {
        if config.showModePicker && elapsedMode {
            return config.elapsedPrimaryTitle ?? "开始正计时"
        }
        return config.primaryTitle
    }
}

/// 自定义 hosting view：确保面板内 SwiftUI 文本框「第一次点击」就能获得焦点并显示光标。
/// 默认 NSHostingView 不接收 first mouse / 不作为 first responder，导致 NSPanel 里点输入框没光标、要点两次。
private final class FocusHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class FocusHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        view = FocusHostingView(rootView: rootView)
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
        // 关键：让 utility 面板能正常成为 key window（默认 becomesKeyOnlyIfNeeded=true 会拒绝键盘焦点，
        // 导致弹窗里的输入框点进去不显示光标）。
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = true

        let result = PanelResult()
        let dismiss: () -> Void = {
            panel.orderOut(nil)
            NSApp.stopModal()
        }
        let root = PracticePromptPanel(config: config, result: result, dismiss: dismiss)
        let controller = FocusHostingController(rootView: root)
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

        // 激活 app：弹窗需要是激活态，SwiftUI 文本框才会真正绘制竖杠光标（否则 key window 不生效、点不出光标）。
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()   // 确保成为 key window，弹窗输入框第一次点击即有光标
        FocusLogger.info("PromptPanel OPEN — title=\(config.title)")
        NSApp.runModal(for: panel)

        // 提醒弹窗常在「app 不在前台」时由定时器触发。关闭弹窗时 runModal 会把主窗口恢复成 key，
        // 把它顶到当前 App 前面——这里把主窗口悄悄收到后面，避免「处理完弹窗，主界面自己跳出来」。
        // 有意的跳转（"暂停一下" -> openPractice -> onOpenMainWindow）会在后续主动呼起主窗口，不受影响。
        if !NSApp.isActive, let main = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isMainWindow }) {
            main.orderBack(nil)
        }

        FocusLogger.info("PromptPanel CLOSED — title=\(config.title) choice=\(String(describing: result.choice))")
        return result
    }
}