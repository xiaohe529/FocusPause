import SwiftUI

/// 极简冷静风设计系统：统一色板 + 统一卡片样式。
///
/// 色彩语义（Color Consistency Lock）：
/// - `focusAccent`（靛蓝）：唯一主色。选中态、主按钮、链接、导航。
/// - `focusActive`（青绿）：仅表示「正在运行」。计时中横幅、呼吸动画、活跃指示。
/// - `focusDanger`（红）：仅危险操作。紧急退出、删除、破坏性确认。
/// - 三个颜色不得交叉使用；新 UI 一律从语义出发选色。
///
/// 圆角系统（Shape Consistency Lock）：控件 8 / 卡片 12 / 弹窗 14，
/// 通过 `FocusRadius` 使用，禁止裸写其他数值。
enum FocusRadius {
    /// 按钮、输入框、chip、横幅等小控件
    static let control: CGFloat = 8
    /// 分组卡片、内容容器
    static let card: CGFloat = 12
    /// 弹窗、模态大块
    static let modal: CGFloat = 14
}

extension Color {
    /// 沉稳靛蓝：主强调色（开启屏蔽、选中态、主按钮）
    static let focusAccent = Color(red: 0.42, green: 0.47, blue: 0.72)
    /// 沉静青绿：屏蔽中/专注中状态
    static let focusActive = Color(red: 0.30, green: 0.60, blue: 0.55)
    /// 低饱和红：错误 / 紧急
    static let focusDanger = Color(red: 0.80, green: 0.35, blue: 0.32)
    /// 卡片底色（自适应明暗）
    static let focusCard = Color.secondary.opacity(0.12)
}

extension View {
    /// 统一卡片样式：圆角 10 + 内边距 + 自适应底色。
    func focusCard(cornerRadius: CGFloat = FocusRadius.card) -> some View {
        self
            .padding(12)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// 统一提示语义：info 用于普通说明，success 用于运行状态，
/// warning 用于需要注意但不是错误的情况，danger 只保留给危险/失败操作。
enum InfoBannerStyle {
    case info
    case success
    case warning
    case danger

    var color: Color {
        switch self {
        case .info: return .focusAccent
        case .success: return .focusActive
        case .warning: return .orange
        case .danger: return .focusDanger
        }
    }

    var defaultIcon: String {
        switch self {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .danger: return "exclamationmark.triangle.fill"
        }
    }
}

/// 统一二级卡片：标题 + 副标题 + 内容，替代各页面手写卡片头。
struct SectionCard<Content: View>: View {
    var title: String? = nil
    var icon: String? = nil
    var subtitle: String? = nil
    var spacing: CGFloat = 12
    private let content: () -> Content

    init(
        title: String? = nil,
        icon: String? = nil,
        subtitle: String? = nil,
        spacing: CGFloat = 12,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let title {
                HStack(spacing: 6) {
                    if let icon {
                        Image(systemName: icon)
                            .foregroundStyle(Color.focusAccent)
                    }
                    Text(title)
                        .font(.headline)
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: FocusRadius.card))
    }
}

/// 弹窗头部：统一的图标、标题和副标题层级。
struct DialogHeader: View {
    var title: String
    var icon: String
    var tint: Color = .focusAccent
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: FocusRadius.control))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 统一密码弹窗：自动聚焦、清晰错误反馈，并避免固定高度造成的空白或截断。
struct PasswordDialogView: View {
    let title: String
    var icon: String = "key.fill"
    var tint: Color = .focusAccent
    var subtitle: String? = nil
    var message: String? = nil
    var confirmTitle: String = "确认"
    var confirmTint: Color = .focusAccent
    var errorMessage: String? = nil
    @Binding var password: String
    var onSubmit: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DialogHeader(
                title: title,
                icon: icon,
                tint: tint,
                subtitle: subtitle
            )

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("屏蔽密码")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DialogSecureField(
                    text: $password,
                    placeholder: "输入密码",
                    autoFocus: true,
                    onSubmit: onSubmit
                )
                .frame(height: 28)
            }

            if let errorMessage {
                InfoBanner(style: .danger) {
                    Text(errorMessage)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                Button(confirmTitle, action: onSubmit)
                    .buttonStyle(AlwaysActiveButtonStyle(color: confirmTint))
            }
            .padding(.top, 2)
        }
        .padding(22)
        .frame(width: 360, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: FocusRadius.modal))
    }
}

/// 统一确认弹窗：主操作突出，破坏性操作使用低饱和红。
struct ConfirmDialogView: View {
    let title: String
    var icon: String = "exclamationmark.triangle.fill"
    var tint: Color = .focusDanger
    var message: String
    var details: [String] = []
    var confirmTitle: String
    var cancelTitle: String = "取消"
    var confirmTint: Color = .focusDanger
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DialogHeader(title: title, icon: icon, tint: tint)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !details.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(details, id: \.self) { detail in
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(tint)
                                .padding(.top, 2)
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(10)
                .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: FocusRadius.control))
            }

            HStack {
                Spacer()
                Button(cancelTitle, action: onCancel)
                    .buttonStyle(.bordered)
                Button(confirmTitle, action: onConfirm)
                    .buttonStyle(AlwaysActiveButtonStyle(color: confirmTint))
            }
            .padding(.top, 2)
        }
        .padding(22)
        .frame(width: 380, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: FocusRadius.modal))
    }
}

/// 新手引导：只在首次配置阶段出现；一旦完成或稍后再说，就不会因暂停屏蔽而重新出现。
struct SetupChecklistView: View {
    @ObservedObject var state: AppState
    @AppStorage("onboardingCompleted") private var completed = false
    @AppStorage("onboardingDismissed") private var dismissed = false

    private var hasEnabledRule: Bool {
        state.blockRules.contains(where: \.enabled) || (state.forceBlockAll && !state.blockRules.isEmpty)
    }

    private var isComplete: Bool {
        hasEnabledRule && state.hasPassword && state.blockingEnabled
    }

    /// 兼容已有配置：只要已设置密码且有规则，就视为已经完成过初始配置。
    private var isExistingSetup: Bool {
        state.hasPassword && !state.blockRules.isEmpty
    }

    private var shouldShow: Bool {
        !completed && !dismissed && !isExistingSetup
    }

    var body: some View {
        if shouldShow {
            SectionCard(
                title: "快速开始",
                icon: "checklist",
                subtitle: "三步即可开始专注。完成后不会再因为停止屏蔽而重新出现。",
                spacing: 10
            ) {
                step(
                    done: hasEnabledRule,
                    title: "添加要屏蔽的网站或 App",
                    detail: "在下方输入域名，或从已安装应用中选择。",
                    actionTitle: hasEnabledRule ? nil : "去添加"
                ) {
                    state.selectedTab = 0
                }

                step(
                    done: state.hasPassword,
                    title: "设置屏蔽密码",
                    detail: "为停止屏蔽和紧急退出增加一道冷静门槛。",
                    actionTitle: state.hasPassword ? nil : "去设置"
                ) {
                    state.showSettingsSheet = true
                }

                step(
                    done: state.blockingEnabled,
                    title: "开启屏蔽",
                    detail: "开启后下方名单会被锁定，避免冲动修改。",
                    actionTitle: state.blockingEnabled ? nil : "开启"
                ) {
                    state.toggleBlocking()
                }
                .disabled(state.isProcessing)

                HStack {
                    Spacer()
                    Button("稍后再说") {
                        dismissed = true
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .onChange(of: isComplete) { _, newValue in
                if newValue {
                    completed = true
                    dismissed = false
                }
            }
        }
    }

    @ViewBuilder
    private func step(
        done: Bool,
        title: String,
        detail: String,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.focusActive : Color.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(done, color: .secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.focusAccent)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 统一横幅组件，避免每个页面手写不同 padding、颜色和按钮层级。
struct InfoBanner<Content: View>: View {
    let style: InfoBannerStyle
    var icon: String?
    var actionTitle: String?
    var actionColor: Color?
    var actionDisabled: Bool
    var action: (() -> Void)?
    var contentFont: Font
    private let content: () -> Content

    init(
        style: InfoBannerStyle,
        icon: String? = nil,
        actionTitle: String? = nil,
        actionColor: Color? = nil,
        actionDisabled: Bool = false,
        contentFont: Font = .subheadline,
        @ViewBuilder content: @escaping () -> Content,
        action: (() -> Void)? = nil
    ) {
        self.style = style
        self.icon = icon
        self.actionTitle = actionTitle
        self.actionColor = actionColor
        self.actionDisabled = actionDisabled
        self.action = action
        self.contentFont = contentFont
        self.content = content
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon ?? style.defaultIcon)
                .foregroundStyle(style.color)
            content()
                .font(contentFont)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(actionColor ?? style.color)
                    .disabled(actionDisabled)
                    .opacity(actionDisabled ? 0.45 : 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(style.color.opacity(0.08), in: RoundedRectangle(cornerRadius: FocusRadius.control))
    }
}

/// 从左到右排列、放不下自动换行的流式布局：每个子视图按自身理想尺寸排布，间距紧凑。
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 二级子分段：紧凑横排卡片（图标 + 标题），尺寸比一级标签小、间距宽松、
/// 选中态用靛蓝浅底描边，与一级标签（实心胶囊）明显区分。
/// 可直接输入任意位数（含个位数）的数值小框：用字符串承载输入，解析后回写。
/// 避免 `TextField(value:format:)` 在 macOS 上不便输入个位数的问题。
struct MinuteField: View {
    let value: Int
    var width: CGFloat = 35
    let onChange: (Int) -> Void
    @State private var text: String

    init(value: Int, width: CGFloat = 35, onChange: @escaping (Int) -> Void) {
        self.value = value
        self.width = width
        self.onChange = onChange
        _text = State(initialValue: String(value))
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .frame(width: width)
            .onChange(of: text) { _, newText in
                let digits = newText.filter { $0.isNumber }
                guard let v = Int(digits), v > 0 else { return }
                onChange(v)
            }
            .onChange(of: value) { _, newValue in
                // 外部（步进器等）变化时同步显示
                if Int(text) != newValue { text = String(newValue) }
            }
    }
}

/// 行内操作按钮组（编辑 / 上移 / 删除）：默认透明隐藏、不可点，
/// `revealed` 为 true 时淡入显示。用于列表条目在鼠标悬停时才露出操作按钮。
struct RowActionButtons: View {
    var revealed: Bool
    var onEdit: (() -> Void)?
    var moveUp: (() -> Void)?
    var canMoveUp: Bool = true
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            if let moveUp {
                Button(action: moveUp) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(!canMoveUp)
            }
            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.focusDanger)
            }
        }
        .opacity(revealed ? 1 : 0)
        .animation(.easeInOut(duration: 0.12), value: revealed)
    }
}

struct SubSegmentCard<T: Hashable>: View {
    struct Option {
        let value: T
        let label: String
        let icon: String
    }

    let options: [Option]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 10) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.icon)
                            .font(.system(size: 14))
                        Text(option.label)
                            .font(.subheadline)
                    }
                    .foregroundStyle(selection == option.value ? Color.focusAccent : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        selection == option.value ? Color.focusAccent.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                selection == option.value ? Color.focusAccent.opacity(0.45) : Color.clear,
                                lineWidth: 1
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

