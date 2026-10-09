import SwiftUI

/// FocusPause 设计系统 —— 参考 magpie 的界面语言。
///
/// 视觉模型（Magpie 三件套）：
/// - **底 / 卡 / 线**：灰色页面底 + 白色圆角卡片 + 1px 细线。分组靠「卡片 + 细线」，
///   而不是把每个元素都填一块底。卡片内用浅一档的细线分隔行。
/// - **一个强调色**：`focusAccent`（靛蓝）。只有真正的主动作才用实心主色；
///   导航、列表、状态一律安静（`.primary` / `.secondary` / `.tertiary`）。
/// - **分段导航**：灰轨道 + 白色选中胶囊（系统分段控件的观感）。
///
/// 状态提示不靠颜色区分（红黄绿是交通灯，不是调色板），差异由图标形状与文案承担。
///
/// 圆角（Shape Consistency Lock）：控件 8 / 卡片 12 / 弹窗 14 / 分段轨道 10（内胶囊 7）。
enum FocusRadius {
    /// 按钮、输入框、chip、横幅等小控件
    static let control: CGFloat = 8
    /// 分组卡片、内容容器
    static let card: CGFloat = 12
    /// 弹窗、模态大块
    static let modal: CGFloat = 14
    /// 主导航 Tab 选中态，比卡片更紧凑但比控件更结构化
    static let primarySegment: CGFloat = 10
    /// 胶囊、圆点等完全圆角元素
    static let pill: CGFloat = 999
}

/// 外观主题：跟随系统 / 浅色 / 深色。
enum AppearanceTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }

    /// 对应的 AppKit 外观；`.system` 用 nil 表示跟随系统。
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

/// 可选的强调色主题（设置里可切换）。默认暖赭。
///
/// 选色约束（改色时请一并复核）：
/// - 每个浅色档配白字的对比度 ≥ 4.5，深色档配近黑字的对比度 ≥ 4.5；
/// - 任意两个强调色的 **浅色档** 之间 ΔE ≥ 25，避免设置里出现「看不出区别的两颗色点」；
/// - 每个强调色与 `focusDanger` 的 ΔE ≥ 25。**这条最容易被破坏**：暖色系一旦偏红
///   （陶土最初是 #B44F3B，与砖红 ΔE 仅 13）就会和危险色混成一片，用户以为
///   「主按钮是危险按钮」。
enum AccentTheme: String, CaseIterable, Identifiable {
    case ochre, clay, teal, moss, indigo, plum, graphite
    var id: String { rawValue }

    var label: String {
        switch self {
        case .ochre:  return "暖赭"
        case .clay:   return "陶土"
        case .teal:   return "青碧"
        case .moss:   return "苔绿"
        case .indigo: return "靛蓝"
        case .plum:   return "紫棠"
        case .graphite: return "石墨"
        }
    }

    /// 浅色 / 深色两档的具体色值（深浅各调一档，保证两种外观下都读得清）。
    var colors: (light: Color, dark: Color) {
        switch self {
        case .ochre:
            return (Color(red: 0.647, green: 0.353, blue: 0.110),   // #A55A1C
                    Color(red: 0.902, green: 0.651, blue: 0.408))   // #E6A668
        case .clay:
            // 去红往棕：原 #B44F3B 与当时的砖红 #BE3A31 几乎同色（ΔE 13），
            // 改成赭褐 #8C5F4B 后与新的 danger #AC342E 拉开到 ΔE 35。
            return (Color(red: 0.549, green: 0.373, blue: 0.294),   // #8C5F4B
                    Color(red: 0.839, green: 0.596, blue: 0.463))   // #D69876
        case .teal:
            return (Color(red: 0.133, green: 0.455, blue: 0.467),   // #227477
                    Color(red: 0.435, green: 0.714, blue: 0.725))   // #6FB6B9
        case .moss:
            return (Color(red: 0.290, green: 0.435, blue: 0.255),   // #4A6F41
                    Color(red: 0.588, green: 0.729, blue: 0.518))   // #96BA84
        case .indigo:
            return (Color(red: 0.286, green: 0.314, blue: 0.667),   // #4950AA
                    Color(red: 0.635, green: 0.663, blue: 0.949))   // #A2A9F2
        case .plum:
            return (Color(red: 0.482, green: 0.290, blue: 0.510),   // #7B4A82
                    Color(red: 0.745, green: 0.576, blue: 0.769))   // #BE93C4
        case .graphite:
            return (Color(red: 0.306, green: 0.306, blue: 0.345),   // #4E4E58
                    Color(red: 0.659, green: 0.659, blue: 0.706))   // #A8A8B4
        }
    }
}

extension Color {
    /// 当前强调色主题。由 `AppState` 在启动 / 设置变化时写入，默认暖赭。
    nonisolated(unsafe) static var currentAccentTheme: AccentTheme = .ochre

    /// 唯一强调色：取自当前主题（默认暖赭 / 陶土橙）。
    /// 为什么默认暖赭：底是中性灰、文字是墨，再配冷色（蓝 / 青）又滑回 AI 模板；
    /// 暖赭「人味」、和灰墨天然搭，低饱和避免变成廉价暖色 slop。
    /// 只用在真正的主动作 / 选中态 / 链接 / 运行中图标上。
    static var focusAccent: Color {
        let c = currentAccentTheme.colors
        return Color(light: c.light, dark: c.dark)
    }

    /// 危险色：解除屏蔽 / 拦截 / 紧急退出这类「破坏性 / 需要三思」的动作。
    /// 用克制的砖红（不是纯红），和墨、灰搭得住；始终配白字。
    /// 与所有强调色的 ΔE 都 ≥ 25（见 `AccentTheme` 的选色约束）。
    static let focusDanger = Color(
        light: Color(red: 0.675, green: 0.204, blue: 0.180),   // #AC342E
        dark:  Color(red: 0.776, green: 0.290, blue: 0.259)    // #C64A42
    )

    /// 高强调墨色：停止 / 确认退出这类要有分量、但不抢暖色的动作。随明暗翻转为近白。
    static let focusInk = Color(
        light: Color(red: 0.110, green: 0.110, blue: 0.130),   // #1c1c21
        dark:  Color(red: 0.929, green: 0.929, blue: 0.945)    // #ededf1
    )

    /// 主色 / 墨色实心按钮上的文字色：随明暗翻转（浅色底→深字，深色底→浅字）。
    static let accentFg = Color(
        light: Color.white,
        dark:  Color(red: 0.090, green: 0.090, blue: 0.110)    // #17171c
    )

    /// 兼容旧调用：内容块底色 = 卡片底。
    static let focusCard = surfaceCard

    /// 页面底（magpie --bg）。
    static let surfaceCanvas = Color(
        light: Color(red: 0.957, green: 0.957, blue: 0.965),   // #f4f4f6
        dark:  Color(red: 0.102, green: 0.102, blue: 0.118)    // #1a1a1e
    )
    /// 卡片 / 列表底（magpie --card）。
    static let surfaceCard = Color(
        light: Color(red: 1.000, green: 1.000, blue: 1.000),   // #ffffff
        dark:  Color(red: 0.137, green: 0.137, blue: 0.153)    // #232327
    )
    /// 控件 / 分段轨道 / chip 底（magpie --pill）。
    static let surfaceWell = Color(
        light: Color(red: 0.945, green: 0.945, blue: 0.957),   // #f1f1f4
        dark:  Color(red: 0.176, green: 0.176, blue: 0.200)    // #2d2d33
    )
    /// 卡片描边（magpie --line）。
    static let surfaceHairline = Color(
        light: Color(red: 0.890, green: 0.890, blue: 0.910),   // #e3e3e8
        dark:  Color(red: 0.200, green: 0.200, blue: 0.224)    // #333339
    )
    /// 卡内分隔线，比描边浅一档（magpie --line-2）。
    static let surfaceDivider = Color(
        light: Color(red: 0.925, green: 0.925, blue: 0.941),   // #ececf0
        dark:  Color(red: 0.173, green: 0.173, blue: 0.196)    // #2c2c32
    )

    /// 用浅色 / 深色两个具体值创建自适应颜色。
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }
}

extension View {
    /// 内容块 → 白色圆角卡片 + 1px 细线（magpie 的 `.card`）。
    /// 分组靠卡片，不再靠填充色块。
    func focusCard(cornerRadius: CGFloat = FocusRadius.card) -> some View {
        self
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.surfaceHairline, lineWidth: 1)
            )
    }

    /// 列表容器：一整块白卡，行之间用更浅的细线分隔（magpie 的 `.card` + `.row`）。
    /// 行自己提供内边距，所以这里不额外加 padding，只负责底、边、裁剪。
    func focusList(cornerRadius: CGFloat = FocusRadius.card) -> some View {
        self
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.surfaceHairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// 组内的一行（多行卡片用）：无独立底，只在行底压一条更浅的细线。
    func focusRow(cornerRadius: CGFloat = FocusRadius.control) -> some View {
        self.overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.surfaceDivider)
                .frame(height: 1)
        }
    }

    /// 可点击的胶囊 chip（magpie 的 pill）：中性底、无描边；选中用浅主色底 + 主色文字。
    func focusChip(isSelected: Bool = false, tint: Color = .focusAccent) -> some View {
        self
            .background(Capsule().fill(isSelected ? tint.opacity(0.12) : Color.surfaceWell))
            .foregroundStyle(isSelected ? tint : Color.primary)
    }

    /// 统一输入框外观：中性底 + 1px 细线。
    /// 聚焦时**不变色、不加聚焦环**——用户明确不喜欢点击输入框后输入框变色的效果。
    func focusField(
        height: CGFloat? = nil,
        horizontalPadding: CGFloat = 10,
        verticalPadding: CGFloat = 7,
        background: Color = .surfaceCard
    ) -> some View {
        self
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, height == nil ? verticalPadding : 0)
            .frame(height: height)
            .background(background, in: RoundedRectangle(cornerRadius: FocusRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FocusRadius.control, style: .continuous)
                    .strokeBorder(Color.surfaceHairline, lineWidth: 1)
            )
    }
}

/// 统一提示语义：info 用于普通说明，success 用于运行状态，
/// warning 用于需要注意但不是错误的情况，danger 只保留给危险/失败操作。
enum InfoBannerStyle {
    case info
    case success
    case warning
    case danger

    /// 提醒不以颜色区分（红黄绿是交通灯，不是调色板）。
    /// 差异由图标形状与文案承担；颜色统一走中性墨色。
    var color: Color { .secondary }

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
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
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
        .focusCard()
    }
}

/// 弹窗头部：统一的图标、标题和副标题层级。
struct DialogHeader: View {
    var title: String
    var icon: String
    var tint: Color = .focusAccent
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // 图标不再包在自身色调的方块里，只保留字形与墨色。
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)

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

/// 弹窗外壳：白卡 + 1px 描边，内容与底部按钮条作为**兄弟节点**垂直排列。
///
/// 关键：按钮条必须参与布局（不能挂在 `.overlay` 上）。挂在 overlay 时内容区不会为它
/// 让位，按钮会直接压在正文上——这正是之前「解除屏蔽 / 结束休息」等弹窗布局错乱的原因。
struct DialogShell<Content: View, Secondary: View, Primary: View>: View {
    var width: CGFloat
    @ViewBuilder var content: () -> Content
    @ViewBuilder var secondary: () -> Secondary
    @ViewBuilder var primary: () -> Primary

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .frame(width: width, alignment: .topLeading)

            Rectangle()
                .fill(Color.surfaceDivider)
                .frame(height: 1)

            // 次要 + 主按钮并排靠右（macOS 惯例）
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                secondary()
                primary()
            }
            .padding(.top, 14)
            .padding(.bottom, 16)
            .padding(.horizontal, 20)
        }
        .frame(width: width)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: FocusRadius.modal, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FocusRadius.modal, style: .continuous)
                .strokeBorder(Color.surfaceHairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: FocusRadius.modal, style: .continuous))
    }
}

/// 冷静期弹窗：实时倒计时 + 大号时间。
/// 必须用自绘弹窗（sheet）而不是系统 `.alert`——系统弹窗内的 TimelineView 不会重绘。
struct CooldownDialogView: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DialogShell(width: 380) {
            DialogHeader(
                title: "冷静期内无法解除屏蔽",
                icon: "lock.clock",
                tint: .focusAccent,
                subtitle: "开启屏蔽后的冷静期，是为了给冲动一个缓冲。"
            )

            // 每秒按当前时钟重算，倒计时逐秒往下走。
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = state.coolDownRemaining(at: context.date)
                VStack(spacing: 4) {
                    Text(coolDownClockString(left))
                        .font(.system(size: 44, weight: .light, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text("剩余冷静时间")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            Text("冷静期结束后才能解除屏蔽；如果已经想清楚了，可以等到时间走完再操作。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        } secondary: {
            EmptyView()
        } primary: {
            Button("知道了") { dismiss() }
                .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
        }
    }
}

/// 把剩余秒数格式化成 mm:ss（分钟可以超过 60）。
func coolDownClockString(_ remaining: TimeInterval) -> String {
    let total = max(0, Int(remaining))
    return String(format: "%02d:%02d", total / 60, total % 60)
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
        DialogShell(width: 380) {
            DialogHeader(title: title, icon: icon, tint: tint, subtitle: subtitle)

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
        } secondary: {
            Button("取消", action: onCancel)
                .buttonStyle(AlwaysActiveTintedButtonStyle())
        } primary: {
            Button(confirmTitle, action: onSubmit)
                .buttonStyle(AlwaysActiveButtonStyle(color: confirmTint))
        }
    }
}

/// 统一确认弹窗：主操作突出，破坏性操作使用低饱和红。
struct ConfirmDialogView: View {
    let title: String
    var icon: String = "exclamationmark.triangle.fill"
    var tint: Color = .focusAccent
    var message: String
    var details: [String] = []
    var confirmTitle: String
    /// 传 nil 时只显示确认按钮（用于纯通知类弹窗）。
    var cancelTitle: String? = "取消"
    var confirmTint: Color = .focusAccent
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        DialogShell(width: 400) {
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
                .background(Color.surfaceWell, in: RoundedRectangle(cornerRadius: FocusRadius.control, style: .continuous))
            }
        } secondary: {
            if let cancelTitle {
                Button(cancelTitle, action: onCancel)
                    .buttonStyle(AlwaysActiveTintedButtonStyle())
            }
        } primary: {
            Button(confirmTitle, action: onConfirm)
                .buttonStyle(AlwaysActiveButtonStyle(color: confirmTint))
        }
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
                subtitle: "三步即可开始专注。完成后不会再因为解除屏蔽而重新出现。",
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
                    detail: "为解除屏蔽和紧急退出增加一道冷静门槛。",
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
                .foregroundStyle(done ? Color.focusAccent : Color.secondary)
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
                .foregroundStyle(.secondary)
            content()
                .font(contentFont)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(actionColor ?? Color.focusAccent)
                    .disabled(actionDisabled)
                    .opacity(actionDisabled ? 0.45 : 1)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 8)
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
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .frame(width: width - 16)
            .focusField(height: 24, horizontalPadding: 8, verticalPadding: 0)
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
        HStack(spacing: 2) {
            if let onEdit {
                actionButton("pencil", tint: .secondary, action: onEdit)
            }
            if let moveUp {
                actionButton("chevron.up", tint: .secondary, disabled: !canMoveUp, action: moveUp)
            }
            if let onDelete {
                actionButton("trash", tint: .focusInk, action: onDelete)
            }
        }
        .opacity(revealed ? 1 : 0)
        .animation(.easeInOut(duration: 0.12), value: revealed)
    }

    /// 悬停才出现的图标操作：统一 26x22 点击区，避免图标过小难以点中。
    private func actionButton(
        _ icon: String,
        tint: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.secondary.opacity(0.4) : tint)
        .disabled(disabled)
    }
}

/// 极简分段控件：只带文字，灰轨道 + 白色选中胶囊（与导航同一套语言）。
/// 用来替换原生 `.segmented` 选择器——后者在墨色 tint 下会变成一整块黑，很重。
///
/// 选中态有两档：
/// - `.capsule`（默认）：灰轨道 + 白胶囊。**这是全局约定**（见 CLAUDE.md 的设计系统一节），
///   设置页、工具箱、定时屏蔽时段等位置都依赖它，不要改默认值。
/// - `.filled`：强调色实心。用于弹窗内的少数关键二选一（例如「倒计时 / 正计时」）——
///   弹窗里白胶囊压在浅灰轨道上几乎看不出选中，二选一必须一眼可辨。
struct MiniSegmented<T: Hashable>: View {
    enum SelectedStyle {
        case capsule
        case filled
    }

    let options: [(value: T, label: String)]
    @Binding var selection: T
    var selectedStyle: SelectedStyle = .capsule

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isSelected = selection == option.value
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(foregroundColor(isSelected: isSelected))
                        .background(
                            backgroundColor(isSelected: isSelected),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(borderColor(isSelected: isSelected), lineWidth: 1)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.surfaceWell, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func foregroundColor(isSelected: Bool) -> Color {
        switch selectedStyle {
        case .capsule: return isSelected ? Color.primary : Color.secondary
        case .filled:  return isSelected ? Color.accentFg : Color.secondary
        }
    }

    private func backgroundColor(isSelected: Bool) -> Color {
        guard isSelected else { return Color.clear }
        return selectedStyle == .filled ? Color.focusAccent : Color.surfaceCard
    }

    private func borderColor(isSelected: Bool) -> Color {
        guard isSelected, selectedStyle == .capsule else { return Color.clear }
        return Color.surfaceHairline
    }
}

struct SubSegmentCard<T: Hashable>: View {
    /// 二级 / 三级导航。刻意**不用**一级导航那套「灰轨道 + 白胶囊」——
    /// 两级同款会看着重复、分不出层级。这里用更轻的「下划线文字」：
    /// 无轨道、无填充，靠颜色与一条下划线表示选中。
    /// `contained`：二级导航，靠左对齐；`plain`：卡片内模式切换，居中。
    enum Variant { case contained, plain }

    struct Option {
        let value: T
        let label: String
        let icon: String
    }

    let options: [Option]
    @Binding var selection: T
    var variant: Variant = .contained

    var body: some View {
        switch variant {
        case .contained: row(leading: false)   // 二级导航居中
        case .plain: row(leading: false)
        }
    }

    private func row(leading: Bool) -> some View {
        HStack(spacing: 18) {   // 文字标签之间留白，而不是挤在一个轨道里
            ForEach(options, id: \.value) { option in
                let isSelected = selection == option.value
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { selection = option.value }
                } label: {
                    tabLabel(option, isSelected: isSelected)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
    }

    private func tabLabel(_ option: Option, isSelected: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: option.icon)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Text(option.label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.focusAccent : Color.secondary)

            // 选中下划线：唯一的状态信号，无填充、无描边。
            Capsule()
                .fill(isSelected ? Color.focusAccent : Color.clear)
                .frame(height: 2)
        }
        .padding(.top, 2)
        .contentShape(Rectangle())
    }
}
