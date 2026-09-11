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
    case grounding        // 点了「五感着陆」，跳转到着陆练习
    case rest(Int)        // 点了「休息一下」，携带休息分钟数
    case secondary        // footer 次按钮（取消）
    case tertiary         // footer 第三按钮（稍后提醒）
    case sectionAction    // 版块内的第二个动作（如「立即屏蔽」）
    case cancel           // 关闭
}

final class PanelResult {
    var choice: PanelChoice = .cancel
    var goal = ""
    var restMinutes = 6
    var restEvent = ""
}

/// 弹窗语义：普通提醒 / 需要注意 / 授权或屏蔽到期等高风险状态。
enum PromptPanelTone {
    case normal
    case warning
    case danger

    var color: Color {
        switch self {
        case .normal: return .focusAccent
        case .warning: return .orange
        case .danger: return .focusDanger
        }
    }

    var badge: String {
        switch self {
        case .normal: return "提醒"
        case .warning: return "注意"
        case .danger: return "待处理"
        }
    }
}

struct PromptPanelConfig {
    var title: String
    var icon: String
    var section1Title: String
    var message: String
    var subtitle: String? = nil
    var tone: PromptPanelTone = .normal
    var presets: [(String, Int)] = []
    var showGoal = false
    var goalPlaceholder: String? = nil
    var actionItems: [PromptItem] = []
    var textItems: [PromptItem] = []
    var primaryTitle = "确定"
    /// 独立主按钮颜色；不填则跟随弹窗语义色。
    var primaryTint: Color? = nil
    /// 主按钮独立区域时的辅助说明，例如「不需要延长？」。
    var primaryHint: String? = nil
    /// 显式的时长确认按钮。提供后，预设/自定义选择必须点它确认；primaryTitle 保持独立动作。
    var durationConfirmTitle: String? = nil
    /// 「倒计时 / 正计时」模式切换（显示在版块顶部）。开启后正计时隐藏时长、主按钮文案用 elapsedPrimaryTitle。
    var showModePicker = false
    /// 正计时时主按钮文案（默认「开始正计时」）。
    var elapsedPrimaryTitle: String? = nil
    /// 版块内主按钮下方的第二个动作（如「立即屏蔽」），返回 .sectionAction。描边风格以示区别于「暂停一下」。
    var sectionActionTitle: String? = nil
    var secondaryTitle: String? = nil
    var tertiaryTitle: String? = nil
    /// 是否显示「暂停一下」；待授权且延长次数用完时可隐藏，优先完成授权。
    var showPause = true
    var pauseHint: String? = nil
    /// 是否显示紧凑的「休息一下」入口。
    var showRest = false
    var restTitle = "休息一下"
    var restPlaceholder = "休息时想做什么？"
    var restDefaultMinutes = 6
    /// 休息事件候选；为空时回退到 actionItems。
    var restOptions: [String] = []
    /// 专注类弹窗有「休息一下」作为替代动作时，可以隐藏通用的「一些提醒」版块；底部随机文字仍可保留。
    var showHints = true
    var showTextHint = true
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
    @State private var restMinutes: Int
    @State private var restEvent = ""
    @State private var customFieldEpoch = 0

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
        _restMinutes = State(initialValue: config.restDefaultMinutes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            section1
            if config.durationConfirmTitle != nil {
                primaryActionSection
            }
            if config.showHints && !config.actionItems.isEmpty {
                hintsSection
            }
            if config.showRest {
                restSection
            }
            if config.showPause {
                pauseSection
            }
            if config.showTextHint && !config.textItems.isEmpty {
                textHintSection
            }
            footer
        }
        .padding(18)
        .frame(width: 390, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            pickRandomTextHint(forceDifferent: false)
            if config.showGoal {
                // DialogTextField requests AppKit first-responder status after it is mounted.
            }
        }
    }

    private var header: some View {
        DialogHeader(
            title: config.title,
            icon: config.icon,
            tint: config.tone.color,
            subtitle: config.subtitle
        )
    }

    private var section1: some View {
        SectionCard(title: config.section1Title, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                Text(config.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if config.showModePicker {
                    Picker("模式", selection: $elapsedMode) {
                        Text("倒计时").tag(false)
                        Text("正计时").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 250)
                }

                if config.showModePicker && elapsedMode {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("不限时专注")
                            .font(.subheadline.weight(.semibold))
                        Text("向下累计时长，自己决定何时结束；结束时需密码，不占用紧急退出次数。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if !config.presets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("预设时间")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ForEach(config.presets, id: \.1) { preset in
                                Button {
                                    duration = .preset(preset.1)
                                    customFieldEpoch += 1
                                } label: {
                                    Text(preset.0)
                                        .frame(maxWidth: .infinity, minHeight: 28)
                                }
                                .buttonStyle(AlwaysActiveButtonStyle(
                                    color: selectedPreset == preset.1 ? .focusActive : .gray
                                ))
                            }
                        }

                        HStack {
                            Text("自定义时间")
                                .font(.subheadline)
                            Spacer()
                            DialogNumberField(number: Binding(
                                get: { customBinding.wrappedValue },
                                set: { duration = .custom(max(1, $0)) }
                            ),
                            alignment: .right
                            )
                                .frame(width: 68)
                                .id(customFieldEpoch)
                            Text("分钟")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if config.showGoal {
                    DialogTextField(
                        text: $goal,
                        placeholder: config.goalPlaceholder ?? "",
                        autoFocus: true
                    )
                }

                if config.durationConfirmTitle == nil {
                    HStack {
                        Spacer()
                        Button {
                            result.goal = goal
                            result.choice = primaryChoice
                            dismiss()
                        } label: {
                            Text(primaryButtonTitle)
                                .frame(minWidth: 92, minHeight: 28)
                        }
                        .buttonStyle(AlwaysActiveButtonStyle(color: config.tone.color))
                        .help(primaryButtonTitle)
                    }
                } else if let durationConfirmTitle = config.durationConfirmTitle {
                    HStack {
                        Spacer()
                        Button {
                            confirmDuration()
                        } label: {
                            Label(durationConfirmTitle, systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .frame(minWidth: 118, minHeight: 26)
                        }
                        .buttonStyle(AlwaysActiveButtonStyle(color: .orange))
                        .help(durationConfirmTitle)
                    }
                }
                if let sectionActionTitle = config.sectionActionTitle {
                    HStack {
                        Spacer()
                        Button {
                            result.goal = goal
                            result.choice = .sectionAction
                            dismiss()
                        } label: {
                            Text(sectionActionTitle)
                                .frame(minWidth: 82, minHeight: 26)
                        }
                        .buttonStyle(AlwaysActiveButtonStyle(color: .focusActive))
                        .help(sectionActionTitle)
                    }
                }
            }
        }
    }

    private var primaryActionSection: some View {
        HStack(spacing: 12) {
            if let primaryHint = config.primaryHint {
                Text(primaryHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                result.goal = goal
                result.choice = .primary
                dismiss()
            } label: {
                Text(primaryButtonTitle)
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 96, minHeight: 30)
            }
            .buttonStyle(AlwaysActiveButtonStyle(color: config.primaryTint ?? config.tone.color))
            .help(primaryButtonTitle)
        }
        .padding(.top, -2)
    }

    private var hintsSection: some View {
        SectionCard(title: "一些提醒", icon: "bell.fill", spacing: 6) {
            FlowLayout(spacing: 5) {
                ForEach(config.actionItems.prefix(4)) { item in
                    Button {
                        showToast()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "hand.point.right")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.focusAccent)
                            Text(item.text)
                                .font(.body)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                        .foregroundStyle(Color.primary)
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
    }

    private var restSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(config.restTitle, systemImage: "cup.and.saucer.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.focusAccent)
                Spacer()
                DialogNumberField(
                    number: $restMinutes,
                    allowedRange: 1...120
                )
                .frame(width: 54)
                Text("分钟")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !restChoices.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(restChoices, id: \.self) { choice in
                        Button {
                            restEvent = restEvent == choice ? "" : choice
                        } label: {
                            Text(choice)
                                .font(.caption)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(
                                    restEvent == choice
                                        ? Color.focusAccent.opacity(0.18)
                                        : Color.secondary.opacity(0.10),
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule().strokeBorder(
                                        restEvent == choice
                                            ? Color.focusAccent.opacity(0.6)
                                            : Color.clear,
                                        lineWidth: 1
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !config.restPlaceholder.isEmpty {
                DialogTextField(
                    text: $restEvent,
                    placeholder: config.restPlaceholder,
                    height: 22
                )
            }

            HStack {
                Spacer()
                Button {
                    result.restMinutes = max(1, restMinutes)
                    result.restEvent = restEvent
                    result.goal = goal
                    result.choice = .rest(max(1, restMinutes))
                    dismiss()
                } label: {
                    Label("休息一下", systemImage: "cup.and.saucer.fill")
                        .frame(minWidth: 76, minHeight: 26)
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
            }
        }
        .padding(10)
        .background(Color.focusAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var restChoices: [String] {
        Array(config.actionItems.prefix(4).map(\.text))
    }

    private var pauseSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    result.goal = goal
                    result.choice = .pause
                    dismiss()
                } label: {
                    Label("暂停一下", systemImage: "pause.circle.fill")
                        .frame(minWidth: 118, minHeight: 28)
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: .focusActive))

                Button {
                    result.goal = goal
                    result.choice = .grounding
                    dismiss()
                } label: {
                    Label("五感着陆", systemImage: "5.circle")
                        .font(.caption)
                        .frame(minWidth: 72, minHeight: 24)
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if let pauseHint = config.pauseHint {
                Text(pauseHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var textHintSection: some View {
        Button {
            pickRandomTextHint(forceDifferent: true)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "quote.opening")
                    .foregroundStyle(Color.focusAccent)
                    .padding(.top, 1)
                Text("「\(config.textItems[textHintIndex].text)」")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: "shuffle")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .font(.body)
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
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

    private var customMinutes: Int {
        switch duration {
        case .preset(let minutes): return minutes
        case .custom(let minutes): return minutes
        }
    }

    private var customBinding: Binding<Int> {
        Binding(
            get: { customMinutes },
            set: { duration = .custom(max(1, $0)) }
        )
    }

    private var primaryChoice: PanelChoice {
        // 显式确认模式下，主按钮不再隐式采用当前选中的时长，避免“点了 5 分钟却按成立即屏蔽”。
        if config.durationConfirmTitle != nil { return .primary }
        if config.showModePicker && elapsedMode { return .elapsed }
        guard !config.presets.isEmpty else { return .primary }
        if case .preset(let minutes) = duration { return .preset(minutes) }
        return .custom(customMinutes)
    }

    private var selectedDurationChoice: PanelChoice {
        if case .preset(let minutes) = duration { return .preset(minutes) }
        return .custom(customMinutes)
    }

    private func confirmDuration() {
        result.goal = goal
        result.choice = selectedDurationChoice
        dismiss()
    }

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