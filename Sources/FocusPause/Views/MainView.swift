import SwiftUI

struct MainView: View {
    @ObservedObject var state: AppState
    @State private var passwordInput = ""
    @State private var passwordError = false
    @State private var emergencyPasswordInput = ""
    @State private var emergencyPasswordError = false
    @State private var scheduledExitPasswordInput = ""
    @State private var scheduledExitPasswordError = false
    let tabLabels = ["屏蔽吧！", "计时模式", "暂停一下"]
    let tabIcons = ["lock.fill", "timer", "pause.circle"]

    var body: some View {
        VStack(spacing: 0) {
            // 一级导航：标题栏下移到窗口顶部，居中的实心胶囊分段（比二级的下划线更重）。
            // 设置只在标题栏齿轮里，这里不重复。
            // 顶部留白多一点：不要贴着标题栏那条线，整条导航才有「落下来」的感觉。
            primaryTabs
                .padding(.top, 22)
                .padding(.bottom, 14)

            // Content — each tab manages its own scrolling
            Group {
                switch state.selectedTab {
                case 0: BlockControlView(state: state)
                case 1: FocusTimerView(state: state)
                case 3: SettingsView(state: state)
                default: PauseView(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 16)
            .padding(.top, 4)

            // Status banners
            VStack(spacing: 8) {
                if state.restActive {
                    InfoBanner(style: .info, icon: "cup.and.saucer.fill") {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text("休息中 · 剩余 \(remainingString(end: state.restEnd)) · 结束后再提醒")
                                .monospacedDigit()
                        }
                    }
                } else if state.focusTimerActive {
                    if state.isElapsedFocus {
                        InfoBanner(style: .success, icon: "lock.fill", actionTitle: "结束", actionColor: .focusInk) {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text("正计时中 · 已用时 \(elapsedString(context.date, start: state.focusTimerStart))")
                                    .monospacedDigit()
                            }
                        } action: { state.requestEndElapsedFocus() }
                    } else {
                        InfoBanner(style: .success, icon: "lock.fill", actionTitle: "紧急退出", actionColor: .focusDanger) {
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                Text("专注计时中 · 剩余 \(remainingString(end: state.focusTimerEnd))")
                                    .monospacedDigit()
                            }
                        } action: { state.requestEmergencyOverride() }
                    }
                } else if state.isScheduledLockActive {
                    InfoBanner(style: .info, icon: "calendar.badge.clock", actionTitle: "紧急退出", actionColor: .focusDanger) {
                        Text("定时屏蔽中 · 本月紧急退出剩余 \(max(0, state.scheduledExitQuota - state.scheduledExitUsesThisMonth))/\(state.scheduledExitQuota)")
                            .monospacedDigit()
                    } action: { state.requestScheduledExit() }
                } else if state.delayedBlockPendingAuth {
                    InfoBanner(style: .danger, actionTitle: "去授权") {
                        Text("屏蔽未生效 · 到点未授权")
                    } action: { state.selectedTab = 1 }
                } else if state.delayedBlockActive {
                    InfoBanner(style: .info, icon: "clock.badge.exclamationmark") {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text("延时屏蔽倒计时 · 剩余 \(remainingString(end: state.delayedBlockEnd)) · 到点自动屏蔽")
                                .monospacedDigit()
                        }
                    }
                } else if !state.scheduledWindows.isEmpty {
                    InfoBanner(style: .info, icon: "calendar.badge.exclamationmark") {
                        Text("已设定 \(state.scheduledWindows.filter(\.enabled).count)/\(state.scheduledWindows.count) 段定时屏蔽")
                            .monospacedDigit()
                    }
                }

                if state.blockingEnabled && !state.hasPassword {
                    InfoBanner(style: .warning, icon: "key.fill", actionTitle: "设置", contentFont: .caption) {
                        Text("未设置屏蔽密码，解除屏蔽无需验证。建议设置，为冲动解除增加一道门槛。")
                    } action: { state.showSettingsSheet = true }
                }

                if let error = state.lastError {
                    InfoBanner(style: .danger, actionTitle: "清除", contentFont: .caption) {
                        Text(error)
                    } action: { state.lastError = nil }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            // Bottom control bar (full-width bar, bottom margin only)
            controlBar
                .padding(.top, 8)
                .padding(.bottom, 16)
        }
        .frame(minWidth: 680, minHeight: 560, alignment: .top)
        .background(Color.surfaceCanvas)
        // 让原生开关 / 分段控件 / 强调按钮统一采用靛蓝主色，而不是系统蓝。
        .tint(Color.focusAccent)
        .sheet(isPresented: $state.showPasswordSheet, onDismiss: {
            passwordInput = ""
            passwordError = false
            state.pendingToggleAction = nil
            state.pendingActionLabel = ""
            state.lastError = nil
        }) {
            PasswordDialogView(
                title: passwordDialogTitle,
                icon: "lock.rotation",
                subtitle: passwordDialogSubtitle,
                message: passwordDialogMessage,
                confirmTitle: "确认",
                errorMessage: passwordError ? "密码错误，请重试" : nil,
                password: $passwordInput,
                onSubmit: verifyPassword,
                onCancel: {
                    state.showPasswordSheet = false
                    passwordInput = ""
                    passwordError = false
                    state.pendingToggleAction = nil
                    state.pendingActionLabel = ""
                    state.lastError = nil
                }
            )
        }
        .sheet(isPresented: $state.showSettingsSheet) {
            EmptyView()
                .frame(width: 1, height: 1)
                .onAppear {
                    state.showSettingsSheet = false
                    state.selectedTab = 3
                }
        }
        .sheet(isPresented: $state.showEndElapsedConfirmation) {
            ConfirmDialogView(
                title: "结束正计时",
                icon: "timer",
                tint: .focusAccent,
                message: "将结束当前正计时。屏蔽保持开启，且不消耗紧急退出次数。",
                confirmTitle: "确认结束",
                confirmTint: .focusAccent
            ) {
                state.endFocusTimerElapsed()
                state.showEndElapsedConfirmation = false
            } onCancel: {
                state.showEndElapsedConfirmation = false
            }
        }
        .sheet(isPresented: $state.showEmergencyOverrideSheet, onDismiss: {
            emergencyPasswordInput = ""
            emergencyPasswordError = false
        }) {
            PasswordDialogView(
                title: "紧急退出专注计时",
                icon: "clock.badge.exclamationmark",
                tint: .focusDanger,
                subtitle: "本月已用 \(state.emergencyUsesThisMonth) / \(state.emergencyQuota) 次",
                message: "紧急退出会立即结束本次专注计时。请先确认已经完成当前任务。",
                confirmTitle: "确认退出",
                confirmTint: .focusDanger,
                errorMessage: emergencyPasswordError ? (state.lastError ?? "密码错误，请重试") : nil,
                password: $emergencyPasswordInput,
                onSubmit: confirmEmergencyOverride,
                onCancel: {
                    state.showEmergencyOverrideSheet = false
                    emergencyPasswordInput = ""
                    emergencyPasswordError = false
                }
            )
        }
        .sheet(isPresented: $state.showScheduledExitSheet, onDismiss: {
            scheduledExitPasswordInput = ""
            scheduledExitPasswordError = false
        }) {
            PasswordDialogView(
                title: "紧急退出定时屏蔽",
                icon: "calendar.badge.exclamationmark",
                tint: .focusDanger,
                subtitle: "本月已用 \(state.scheduledExitUsesThisMonth) / \(state.scheduledExitQuota) 次（与专注计时独立）",
                message: "退出后本次定时屏蔽会停止。请确认不再需要这段保护。",
                confirmTitle: "确认退出",
                confirmTint: .focusDanger,
                errorMessage: scheduledExitPasswordError ? (state.lastError ?? "密码错误，请重试") : nil,
                password: $scheduledExitPasswordInput,
                onSubmit: confirmScheduledExit,
                onCancel: {
                    state.showScheduledExitSheet = false
                    scheduledExitPasswordInput = ""
                    scheduledExitPasswordError = false
                }
            )
        }
        // 用自绘弹窗而不是系统 .alert：系统弹窗里的 TimelineView 不会重绘，
        // 倒计时会卡在打开那一刻不动。
        .sheet(isPresented: $state.showCooldownAlert) {
            CooldownDialogView(state: state)
        }
        // 与其他弹窗统一：自绘 DialogShell（白卡 + 主题色按钮），不用系统 .alert
        // （系统弹窗的默认按钮在无窗口 key 时会是灰/黑色，与其余 UI 不一致）。
        .sheet(isPresented: $state.showEmergencyQuotaAlert) {
            ConfirmDialogView(
                title: "紧急退出次数已用完",
                icon: "exclamationmark.triangle.fill",
                tint: .focusAccent,
                message: state.emergencyQuotaAlertMessage,
                confirmTitle: "知道了",
                cancelTitle: nil
            ) {
                state.showEmergencyQuotaAlert = false
            } onCancel: {
                state.showEmergencyQuotaAlert = false
            }
        }
    }

    // MARK: - 一级导航

    /// 一级导航：居中的实心胶囊分段（比二级更重）。
    /// 设置入口只在标题栏（`TitlebarTabsView` 的齿轮），这里不再重复。
    private var primaryTabs: some View {
        // 标题之间疏开：只在项与项之间留白，胶囊本身尺寸不变，读起来更松弛。
        HStack(spacing: 20) {
            ForEach(0..<tabLabels.count, id: \.self) { i in
                primaryTabButton(i)
            }
        }
        .fixedSize()
    }

    private func primaryTabButton(_ i: Int) -> some View {
        let isSelected = state.selectedTab == i
        return Button {
            withAnimation(.easeOut(duration: 0.16)) { state.selectedTab = i }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tabIcons[i])
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                Text(tabLabels[i])
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .fixedSize()
            }
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(height: 30)
            // 选中 = 强调色实心胶囊（一级导航的重音），未选 = 安静的次要文字。
            .foregroundStyle(isSelected ? Color.accentFg : Color.secondary)
            .background(
                isSelected ? Color.focusAccent : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var passwordDialogTitle: String {
        switch state.pendingActionLabel {
        case "解除屏蔽": return "确认解除屏蔽"
        case "取消延时计时": return "确认取消延时计时"
        case "删除条目": return "确认删除条目"
        default: return "输入密码\(state.pendingActionLabel)"
        }
    }

    private var passwordDialogSubtitle: String {
        switch state.pendingActionLabel {
        case "解除屏蔽": return "解除后要做什么？先确认这是必要的。"
        case "取消延时计时": return "取消后将不会自动开启屏蔽。"
        case "删除条目": return "删除后需要重新添加这条规则。"
        default: return "输入屏蔽密码后才会继续本次操作。"
        }
    }

    private var passwordDialogMessage: String? {
        guard state.pendingActionLabel == "解除屏蔽" else { return nil }
        return "如果只是想休息一下，可以先去「暂停一下」。确有需要时，再输入密码解除。"
    }

    private func confirmEmergencyOverride() {
        let ok = state.emergencyOverride(password: emergencyPasswordInput)
        if ok {
            state.showEmergencyOverrideSheet = false
            emergencyPasswordInput = ""
            emergencyPasswordError = false
        } else {
            emergencyPasswordError = true
        }
    }

    private func confirmScheduledExit() {
        let ok = state.scheduledBlockEmergencyExit(password: scheduledExitPasswordInput)
        if ok {
            state.showScheduledExitSheet = false
            scheduledExitPasswordInput = ""
            scheduledExitPasswordError = false
        } else {
            scheduledExitPasswordError = true
        }
    }

    private func verifyPassword() {
        if KeychainPassword.verify(passwordInput) {
            passwordError = false
            passwordInput = ""
            state.showPasswordSheet = false
            state.pendingActionLabel = ""
            state.pendingToggleAction?()
        } else {
            passwordError = true
        }
    }

    // MARK: - Bottom control bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            // 状态徽标：圆角方块 + 锁形图标（比裸露的 lock.shield 更精致、更像一个「状态点」）。
            Image(systemName: state.blockingEnabled ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(state.blockingEnabled ? Color.focusAccent : Color.secondary)
                .frame(width: 30, height: 30)
                .background(
                    (state.blockingEnabled ? Color.focusAccent.opacity(0.14) : Color.surfaceWell),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            if state.isProcessing {
                ProgressView().controlSize(.small)
                Text("处理中…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(state.blockingEnabled ? "屏蔽中" : "已解除")
                    .font(.subheadline)
            }

            if state.blockingEnabled {
                listLockedBadge
            }

            Spacer()

            Button(action: {
                if state.delayedBlockActive {
                    state.blockNow()
                } else {
                    state.toggleBlocking()
                }
            }) {
                Text(controlButtonTitle)
                    .font(.subheadline)
            }
            .buttonStyle(AlwaysActiveButtonStyle(color: controlButtonColor))
            .disabled(state.isProcessing)

        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 58)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.surfaceHairline)
                .frame(height: 1)
        }
        .background(Color.surfaceCanvas)
    }

    /// 延时屏蔽倒计时期间，主按钮变为「立即屏蔽」。
    private var controlButtonTitle: String {
        if state.delayedBlockActive { return "立即屏蔽" }
        return state.blockingEnabled ? "解除屏蔽" : "开启屏蔽"
    }

    private var controlButtonColor: Color {
        // 「立即屏蔽」是紧急动作 → 砖红；「开启 / 解除屏蔽」都是常规操作 → 主题色。
        if state.delayedBlockActive { return .focusDanger }
        return .focusAccent
    }

    private var listLockedBadge: some View {
        Label("屏蔽名单可增不可减", systemImage: "lock.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }


}

/// 正计时已用时（HH:MM:SS）。
private func elapsedString(_ now: Date, start: Date?) -> String {
    guard let start else { return "00:00" }
    let total = max(0, Int(now.timeIntervalSince(start)))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%02d:%02d", m, s)
}

private func remainingString(end: Date?) -> String {
    guard let end, end > Date() else { return "00:00" }
    let remaining = Int(end.timeIntervalSince(Date()))
    let mins = remaining / 60
    let secs = remaining % 60
    return String(format: "%02d:%02d", mins, secs)
}


private func coolDownString(_ remaining: TimeInterval) -> String {
    let total = Int(remaining)
    let mins = total / 60
    let secs = total % 60
    return String(format: "%02d:%02d", mins, secs)
}

extension AppState {
    /// 冷静期剩余（相对某个时刻），用于倒计时弹窗的实时显示。
    func coolDownRemaining(at date: Date) -> TimeInterval {
        guard let end = coolDownEndsAt else { return 0 }
        return max(0, end.timeIntervalSince(date))
    }
}
