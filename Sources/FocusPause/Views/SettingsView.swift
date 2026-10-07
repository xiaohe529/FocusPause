import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var state: AppState

    /// 未屏蔽提醒间隔（可直接输入）。
    private var reminderIntervalBinding: Binding<Int> {
        Binding(get: { state.reminderIntervalMinutes },
                set: { state.setReminderInterval(minutes: $0) })
    }
    /// 屏蔽中未专注提醒间隔（可直接输入）。
    private var blockingNoFocusIntervalBinding: Binding<Int> {
        Binding(get: { state.blockingNoFocusIntervalMinutes },
                set: { state.setBlockingNoFocusInterval(minutes: $0) })
    }
    /// 冷静期时长（可直接输入）。
    private var coolingMinutesBinding: Binding<Int> {
        Binding(get: { state.coolingMinutes },
                set: { state.setCoolingMinutes($0) })
    }

    @State private var showPasswordSheet = false
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var passwordError: String = ""
    @State private var focusQuotaDraft: Int?
    @State private var scheduledQuotaDraft: Int?
    @State private var showBreakGlassSetup = false
    @State private var breakGlassSetupDisabling = false
    @State private var showBreakGlassUnlock = false
    @State private var showBreakGlassCancel = false
    @State private var recoveryInput1 = ""
    @State private var recoveryInput2 = ""
    @State private var revealedPassword: String?
    @State private var recoveryError: String = ""

    @State private var deletePwdInput1 = ""
    @State private var deletePwdInput2 = ""
    @State private var deletePwdError: String = ""
    @State private var deletePwdSuccess = false

    @State private var updateStatus: UpdateStatus?
    @State private var isCheckingUpdate = false
    @State private var isDownloading = false

    @FocusState private var passwordFieldFocus: PasswordField?

    enum PasswordField: Hashable { case old, new, confirm }


    var body: some View {
        // 直接住在主窗口里：内容区自己滚动，宽度自适应窗口，不再固定成小窗尺寸。
        ScrollView {
            // 分组只靠留白：相关项贴紧、无关分组拉开，不再每节之间钉一条分割线。
            VStack(alignment: .leading, spacing: 28) {
                generalSection
                appearanceSection
                reminderSection
                coolingSection
                emergencyQuotaSection
                reminderAfterBlockSection
                passwordSection
                advancedSection
                updateSection
            }
            .padding(.vertical, 20)
            .padding(.horizontal)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(Color.focusAccent)
        .sheet(isPresented: $showBreakGlassSetup, onDismiss: {
            breakGlassSetupDisabling = false
        }) {
            BreakGlassDialogView(
                title: state.breakGlassEnabled ? "关闭应急解锁" : "启用应急解锁",
                icon: "lock.open.rotation",
                message: state.breakGlassEnabled
                    ? "关闭后，紧急退出次数用完时将没有备用解锁方式。当前屏蔽和计时不会改变。"
                    : "仅用于紧急退出次数用完后的真实紧急情况。发起解锁时仍需输入密码，并等待 5 分钟冷静期。",
                requiresPassword: false,
                submitTitle: state.breakGlassEnabled ? "确认关闭" : "确认启用"
            ) { _, _ in
                let succeeded = state.setBreakGlassEnabled(!state.breakGlassEnabled)
                return succeeded ? nil : (state.lastError ?? "无法更改应急解锁设置")
            }
        }
        .sheet(isPresented: $showBreakGlassUnlock, onDismiss: {
            state.lastError = nil
        }) {
            BreakGlassDialogView(
                title: "发起应急解锁",
                icon: "lock.open.rotation",
                message: "输入确认语句和密码后进入 5 分钟冷静期；冷静期内可放弃，结束前不会解除屏蔽。",
                requiresPassword: true,
                requiresConfirmationPhrase: true,
                submitTitle: "进入冷静期"
            ) { password, phrase in
                let succeeded = state.startBreakGlassUnlock(password: password, confirmationPhrase: phrase)
                return succeeded ? nil : (state.lastError ?? "验证未通过，请重新输入。")
            }
        }
        .sheet(isPresented: $showBreakGlassCancel) {
            ConfirmDialogView(
                title: "放弃应急解锁",
                icon: "xmark.circle",
                tint: .focusAccent,
                message: "将结束当前冷静期并保持所有屏蔽开启，不会解除任何规则。",
                confirmTitle: "放弃解锁",
                confirmTint: .focusAccent
            ) {
                state.cancelBreakGlassUnlock()
            } onCancel: {
                showBreakGlassCancel = false
            }
        }
        .onAppear {
            // 打开设置时不要自动把焦点落进任何输入框。
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .sheet(isPresented: $showPasswordSheet, onDismiss: resetPasswordFields) {
            passwordSheet
        }
    }

    /// 后台助手状态色：正常 = 运行色，异常/需要修复 = 注意色。
    private var helperStatusTint: Color {
        if state.helperNeedsRepair { return .secondary }
        return state.helperInstalled ? .focusAccent : .secondary
    }

    // MARK: - 通用

    // MARK: - 外观（主题 + 强调色）

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("外观")
            VStack(alignment: .leading, spacing: 14) {
                // 外观主题：跟随系统 / 浅色 / 深色
                HStack {
                    Text("主题")
                        .font(.subheadline)
                    Spacer()
                    MiniSegmented(
                        options: [
                            (AppearanceTheme.system, "跟随系统"),
                            (AppearanceTheme.light, "浅色"),
                            (AppearanceTheme.dark, "深色"),
                        ],
                        selection: Binding(
                            get: { state.appearanceTheme },
                            set: { state.setAppearanceTheme($0) }
                        )
                    )
                    .frame(width: 240)
                }

                Divider()

                // 强调色：四选一
                VStack(alignment: .leading, spacing: 8) {
                    Text("强调色")
                        .font(.subheadline)
                    HStack(spacing: 16) {
                        ForEach(AccentTheme.allCases) { theme in
                            accentSwatch(theme)
                        }
                        Spacer()
                    }
                    Text("用在主按钮、当前分区、选中项上。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .focusCard()
        }
    }

    /// 单个强调色样：圆形色块；选中时加一圈描边。
    private func accentSwatch(_ theme: AccentTheme) -> some View {
        let c = theme.colors
        let color = Color(light: c.light, dark: c.dark)
        let isSelected = state.accentTheme == theme
        return Button {
            state.setAccentTheme(theme)
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.55 : 0), lineWidth: 2)
                            .padding(-4)
                    )
                Text(theme.label)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(theme.label)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("通用")
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $state.launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("开机启动")
                            .font(.subheadline)
                        Text("登录时自动启动 Focus&Pause")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(AlwaysActiveSwitchStyle())
                .onChange(of: state.launchAtLogin) { _, v in state.setLaunchAtLogin(v) }

                HStack {
                    Image(systemName: state.helperNeedsRepair ? "exclamationmark.shield.fill" : (state.helperInstalled ? "checkmark.shield.fill" : "exclamationmark.shield.fill"))
                        .foregroundStyle(helperStatusTint)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("后台助手")
                            .font(.subheadline)
                        Text(state.helperNeedsRepair
                             ? "已运行，但需要安全修复"
                             : state.helperInstalled
                                 ? "已安装；删除 App 后会自动清理屏蔽"
                                 : "未安装，首次操作将请求授权")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !state.helperInstalled || state.helperNeedsRepair {
                        Button {
                            Task { await state.installHelper() }
                        } label: {
                            Text(state.isInstallingHelper ? "安装中…" : (state.helperNeedsRepair ? "修复" : "安装"))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .focusCard()
        }
    }

    // MARK: - 延时屏蔽

    // MARK: - 定时提醒

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("定时提醒")
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { state.reminderEnabled },
                    set: { state.setReminderEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("未屏蔽时定时提醒")
                            .font(.subheadline)
                        Text("未开启屏蔽时，每隔指定时间弹窗提醒")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(AlwaysActiveSwitchStyle())

                HStack {
                    Text("提醒间隔")
                        .font(.subheadline)
                    Spacer()
                    MinuteField(value: state.reminderIntervalMinutes) { state.setReminderInterval(minutes: $0) }
                    Text("分钟")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Stepper("", value: reminderIntervalBinding, in: 1...240, step: 5)
                        .labelsHidden()
                }
                Text("屏蔽中、专注计时中、延时屏蔽中均不弹提醒；可直接输入数值。未屏蔽提醒点「稍后提醒」，也按此间隔再次提醒。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle(isOn: Binding(
                    get: { state.remindBlockingNoFocus },
                    set: { state.setRemindBlockingNoFocus($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("屏蔽中未专注时提醒")
                            .font(.subheadline)
                        Text("屏蔽已开启却没有专注计时时，每隔指定时间弹窗提醒")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(AlwaysActiveSwitchStyle())

                HStack {
                    Text("提醒间隔")
                        .font(.subheadline)
                    Spacer()
                    MinuteField(value: state.blockingNoFocusIntervalMinutes) { state.setBlockingNoFocusInterval(minutes: $0) }
                    Text("分钟")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Stepper("", value: blockingNoFocusIntervalBinding, in: 5...240, step: 5)
                        .labelsHidden()
                }
                Text("专注计时进行中不提醒；「已屏蔽未专注」「屏蔽已开启」「专注计时结束」等的「稍后提醒」，也按此间隔再次提醒。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .focusCard()
        }
    }

    // MARK: - 冷静期

    private var coolingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("冷静期")
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { state.coolingEnabled },
                    set: { state.setCoolingEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("屏蔽后冷静期")
                            .font(.subheadline)
                        Text("开启屏蔽后，冷静期内无法解除屏蔽")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(AlwaysActiveSwitchStyle())

                if state.coolingEnabled {
                    HStack {
                        Text("冷静期时长")
                            .font(.subheadline)
                        Spacer()
                        MinuteField(value: state.coolingMinutes) { state.setCoolingMinutes($0) }
                        Text("分钟")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Stepper("", value: coolingMinutesBinding, in: 1...240, step: 5)
                            .labelsHidden()
                    }
                }
            }
            .focusCard()
        }
    }

    // MARK: - 屏蔽提醒

    private var reminderAfterBlockSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("屏蔽提醒")
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { state.remindFocusTimerAfterBlock },
                    set: {
                        state.setRemindFocusTimerAfterBlock($0)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("屏蔽后提醒专注计时")
                            .font(.subheadline)
                        Text("开启屏蔽后，弹窗询问是否设置专注计时")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(AlwaysActiveSwitchStyle())

                Toggle(isOn: Binding(
                    get: { state.remindDelayedBlockAfterUnblock },
                    set: {
                        state.setRemindDelayedBlockAfterUnblock($0)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("解除屏蔽后提醒延时屏蔽")
                            .font(.subheadline)
                        Text("解除屏蔽后，弹窗询问是否设置延时屏蔽")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(AlwaysActiveSwitchStyle())
            }
            .focusCard()
        }
    }

    // MARK: - 紧急退出额度

    private var emergencyQuotaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("紧急退出额度")
            Text("专注计时与定时屏蔽各自的「紧急退出」每月次数上限（1–5）。设定后当月锁定，下个月才能再改。")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                quotaRow(
                    title: "专注计时",
                    value: state.emergencyQuota,
                    locked: state.emergencyQuotaLockedThisMonth,
                    draft: $focusQuotaDraft
                ) { newValue in
                    let ok = state.setEmergencyQuota(newValue)
                    if ok { focusQuotaDraft = nil }
                    return ok
                }
                Divider()
                quotaRow(
                    title: "定时屏蔽",
                    value: state.scheduledExitQuota,
                    locked: state.scheduledExitQuotaLockedThisMonth,
                    draft: $scheduledQuotaDraft
                ) { newValue in
                    let ok = state.setScheduledExitQuota(newValue)
                    if ok { scheduledQuotaDraft = nil }
                    return ok
                }
            }
            .focusCard()
        }
    }

    private func quotaRow(
        title: String,
        value: Int,
        locked: Bool,
        draft: Binding<Int?>,
        onConfirm: @escaping (Int) -> Bool
    ) -> some View {
        let displayedValue = draft.wrappedValue ?? value
        let hasDraft = draft.wrappedValue != nil && draft.wrappedValue != value

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                HStack(spacing: 8) {
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(displayedValue)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .frame(minWidth: 24, alignment: .trailing)
                    Stepper("", value: Binding(
                        get: { displayedValue },
                        set: { draft.wrappedValue = $0 }
                    ), in: 1...5)
                    .labelsHidden()
                    .disabled(locked)
                }
            }
            if locked {
                Text("本月已设置，下个月开放调整")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if hasDraft {
                HStack {
                    Spacer()
                    Button {
                        _ = onConfirm(draft.wrappedValue ?? value)
                    } label: {
                        Label("确认调整", systemImage: "checkmark")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(AlwaysActiveTintedButtonStyle(color: .focusAccent))

                    Button("取消") {
                        draft.wrappedValue = nil
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 密码

    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("密码")
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "key")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("屏蔽密码")
                            .font(.subheadline)
                        Text(state.hasPassword ? "已设置" : "未设置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(state.hasPassword ? "修改" : "设置") {
                        resetPasswordFields()
                        showPasswordSheet = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Text("设置密码后，停止屏蔽需验证密码，为冲动解除增加一道门槛。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .focusCard()
        }
    }

    // MARK: - 高级

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("高级")
            VStack(alignment: .leading, spacing: 8) {
                breakGlassCard

                Divider()

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("为防止误操作，请输入恢复码 `123456789` 两次以查看当前屏蔽密码。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        SecureField("恢复码", text: $recoveryInput1)
                            .textFieldStyle(.plain)
                            .focusField()
                        SecureField("再次输入恢复码", text: $recoveryInput2)
                            .textFieldStyle(.plain)
                            .focusField()
                            .onSubmit { recoverPassword() }
                        Button {
                            recoverPassword()
                        } label: {
                            Label("显示密码", systemImage: "eye")
                        }
                        .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
                        .disabled(recoveryInput1.isEmpty || recoveryInput1 != recoveryInput2)
                        if !recoveryError.isEmpty {
                            Text(recoveryError)
                                .font(.caption)
                                .foregroundStyle(Color.focusInk)
                        }
                        if let pwd = revealedPassword {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("当前屏蔽密码")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(pwd)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: FocusRadius.control))
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("忘记密码？")
                        .font(.subheadline)
                }

                Divider()

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("删除密码后，停止屏蔽将不再需要验证。请输入恢复码 `123456789` 两次以确认删除。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        SecureField("恢复码", text: $deletePwdInput1)
                            .textFieldStyle(.plain)
                            .focusField()
                        SecureField("再次输入恢复码", text: $deletePwdInput2)
                            .textFieldStyle(.plain)
                            .focusField()
                            .onSubmit { deletePassword() }
                        Button {
                            deletePassword()
                        } label: {
                            Label("删除密码", systemImage: "trash")
                        }
                        .buttonStyle(AlwaysActiveButtonStyle(color: .focusDanger))
                        .disabled(deletePwdInput1.isEmpty || deletePwdInput1 != deletePwdInput2)
                        if !deletePwdError.isEmpty {
                            Text(deletePwdError)
                                .font(.caption)
                                .foregroundStyle(Color.focusInk)
                        }
                        if deletePwdSuccess {
                            Text("密码已删除")
                                .font(.caption)
                                .foregroundStyle(Color.focusAccent)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("删除密码")
                        .font(.subheadline)
                }
            }
            .focusCard()
        }
    }

    // MARK: - Break-glass

    private var breakGlassCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: state.breakGlassEnabled ? "lock.open.rotation" : "lock.rotation")
                    .foregroundStyle(state.breakGlassEnabled ? Color.focusInk : Color.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text("应急解锁")
                        .font(.subheadline)
                    Text(state.breakGlassEnabled ? "已启用" : "未启用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(state.breakGlassEnabled ? "关闭" : "启用") {
                    breakGlassSetupDisabling = state.breakGlassEnabled
                    showBreakGlassSetup = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(state.breakGlassEnabled ? !state.canCloseBreakGlass : !(state.canConfigureBreakGlass || state.canEnableBreakGlassDuringLock))
            }

            if let day = state.breakGlassLastAttemptDay {
                Text("最近发起日期：\(day)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if state.breakGlassEnabled && state.canStartBreakGlassUnlock() {
                Button {
                    showBreakGlassUnlock = true
                } label: {
                    Label("发起应急解锁", systemImage: "lock.open.rotation")
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: .focusDanger))
            } else if let cooldownEnd = state.breakGlassCooldownEnd {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 6) {
                        if state.isBreakGlassReadyToComplete(at: context.date) {
                            Button {
                                Task { await state.completeBreakGlassUnlock() }
                            } label: {
                                Label("确认解除所有屏蔽", systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(AlwaysActiveButtonStyle(color: .focusDanger))
                        } else {
                            let remaining = max(0, Int(cooldownEnd.timeIntervalSince(context.date)))
                            Text("冷静期剩余 \(remaining / 60):\(String(format: "%02d", remaining % 60))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Button {
                                showBreakGlassCancel = true
                            } label: {
                                Label("放弃解锁，保持屏蔽", systemImage: "xmark.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            Text("最后的备用解锁方式：满足条件后点击“应急解锁”，输入确认语句和密码进入 5 分钟冷静期；冷静期内可放弃并保持屏蔽，结束后才确认解除所有屏蔽。每天最多发起 1 次。屏蔽进行中也可以从这里启用。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .focusCard()
    }

    // MARK: - 软件更新

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("软件更新")
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前版本 \(Updater.currentVersion)")
                            .font(.subheadline)
                        Text(updateStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isCheckingUpdate {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("检查更新") {
                            Task { await checkForUpdates() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isDownloading)
                    }
                }
                if case .available(let version, let downloadURL, let releaseURL) = updateStatus {
                    Button {
                        if let downloadURL {
                            Task { await downloadAndOpen(downloadURL) }
                        } else {
                            NSWorkspace.shared.open(releaseURL)
                        }
                    } label: {
                        Label(
                            isDownloading ? "下载中…" : (downloadURL != nil ? "下载 v\(version)" : "前往发布页"),
                            systemImage: downloadURL != nil ? "arrow.down.circle" : "arrow.up.right.square"
                        )
                    }
                    .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
                    .disabled(isDownloading)
                }
            }
            .focusCard()
        }
    }

    private var updateStatusText: String {
        switch updateStatus {
        case nil:
            return "从 Gitee 检查是否有新版本"
        case .upToDate?:
            return "已是最新版本"
        case .available(let version, _, _)?:
            return "发现新版本 v\(version)"
        case .failed(let message)?:
            return message
        }
    }

    private func checkForUpdates() async {
        isCheckingUpdate = true
        updateStatus = nil
        let status = await Updater.checkForUpdates()
        updateStatus = status
        isCheckingUpdate = false
    }

    private func downloadAndOpen(_ url: URL) async {
        isDownloading = true
        defer { isDownloading = false }
        if let problem = await Updater.downloadAndOpen(url) {
            updateStatus = .failed(problem)
            return
        }
    }

    // MARK: - 密码修改 sheet

    private var passwordSheet: some View {
        // 与其它弹窗统一：DialogShell 白卡 + 自定义输入框 + 主题色按钮。
        // 之前这里用的是原生 .roundedBorder / .borderedProminent，所以是系统蓝、跟别处不一致。
        DialogShell(width: 380) {
            DialogHeader(
                title: state.hasPassword ? "修改屏蔽密码" : "设置屏蔽密码",
                icon: "key.fill",
                tint: .focusAccent,
                subtitle: state.hasPassword
                    ? "需要先输入旧密码；新密码用于停止屏蔽与紧急退出。"
                    : "设置后，停止屏蔽需验证密码。"
            )

            VStack(alignment: .leading, spacing: 10) {
                if state.hasPassword {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("旧密码").font(.caption).foregroundStyle(.secondary)
                        DialogSecureField(text: $oldPassword, placeholder: "输入旧密码")
                            .frame(height: 26)
                            .focused($passwordFieldFocus, equals: .old)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.hasPassword ? "新密码" : "密码")
                        .font(.caption).foregroundStyle(.secondary)
                    DialogSecureField(text: $newPassword,
                                      placeholder: state.hasPassword ? "输入新密码" : "输入密码")
                        .frame(height: 26)
                        .focused($passwordFieldFocus, equals: .new)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("确认密码").font(.caption).foregroundStyle(.secondary)
                    DialogSecureField(text: $confirmPassword, placeholder: "再次输入")
                        .frame(height: 26)
                        .focused($passwordFieldFocus, equals: .confirm)
                        .onSubmit { savePassword() }
                }
            }

            if !passwordError.isEmpty {
                Text(passwordError)
                    .font(.caption)
                    .foregroundStyle(Color.focusDanger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } secondary: {
            Button("取消") { showPasswordSheet = false }
                .buttonStyle(AlwaysActiveTintedButtonStyle())
        } primary: {
            Button(state.hasPassword ? "保存" : "设置") { savePassword() }
                .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
                .disabled(newPassword != confirmPassword || newPassword.isEmpty)
        }
        .onAppear {
            DispatchQueue.main.async {
                passwordFieldFocus = state.hasPassword ? .old : .new
            }
        }
    }

    private func resetPasswordFields() {
        oldPassword = ""
        newPassword = ""
        confirmPassword = ""
        passwordError = ""
    }

    private func savePassword() {
        guard newPassword == confirmPassword else {
            passwordError = "两次输入不一致"
            return
        }
        guard !newPassword.isEmpty else {
            passwordError = "密码不能为空"
            return
        }
        if state.hasPassword {
            guard !oldPassword.isEmpty else {
                passwordError = "请输入旧密码"
                return
            }
            guard KeychainPassword.verify(oldPassword) else {
                passwordError = "旧密码错误"
                return
            }
        }
        state.setPassword(newPassword)
        showPasswordSheet = false
    }

    // MARK: - 找回密码 / 删除密码

    private func recoverPassword() {
        guard recoveryInput1 == "123456789", recoveryInput1 == recoveryInput2 else {
            recoveryError = "恢复码不正确，需输入 123456789 且两次一致"
            revealedPassword = nil
            return
        }
        recoveryError = ""
        if let pwd = KeychainPassword.load(), !pwd.isEmpty {
            revealedPassword = pwd
        } else {
            revealedPassword = nil
            recoveryError = "尚未设置屏蔽密码"
        }
    }

    private func deletePassword() {
        guard deletePwdInput1 == "123456789", deletePwdInput1 == deletePwdInput2 else {
            deletePwdError = "恢复码不正确，需输入 123456789 且两次一致"
            deletePwdSuccess = false
            return
        }
        guard KeychainPassword.load() != nil else {
            deletePwdError = "尚未设置屏蔽密码"
            deletePwdSuccess = false
            return
        }
        deletePwdError = ""
        KeychainPassword.delete()
        state.hasPassword = false
        deletePwdSuccess = true
        deletePwdInput1 = ""
        deletePwdInput2 = ""
        FocusLogger.info("Password deleted via settings")
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }
}
