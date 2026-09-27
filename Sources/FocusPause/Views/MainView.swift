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
    let tabIcons = ["shield", "timer", "pause.circle"]

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar — soft segmented style
            HStack(spacing: 2) {
                ForEach(0..<tabLabels.count, id: \.self) { i in
                    Button {
                        state.selectedTab = i
                    } label: {
                        Label(tabLabels[i], systemImage: tabIcons[i])
                            .font(.body.weight(state.selectedTab == i ? .semibold : .regular))
                            .padding(.vertical, 7)
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 34)
                            .foregroundStyle(state.selectedTab == i ? .white : .secondary)
                            .background(
                                state.selectedTab == i ? Color.focusAccent : Color.clear,
                                in: Capsule()
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // Content — each tab manages its own scrolling
            Group {
                switch state.selectedTab {
                case 0: BlockControlView(state: state)
                case 1: FocusTimerView(state: state)
                default: PauseView(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal)
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
                        InfoBanner(style: .success, icon: "lock.fill", actionTitle: "结束", actionColor: .focusDanger) {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text("正计时中 · 已用时 \(elapsedString(context.date, start: state.focusTimerStart))")
                                    .monospacedDigit()
                            }
                        } action: { state.requestEndElapsedFocus() }
                    } else {
                        InfoBanner(style: .success, icon: "lock.fill", actionTitle: "紧急退出", actionColor: .focusDanger, actionDisabled: state.emergencyUsesThisMonth >= state.emergencyQuota) {
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                Text("专注计时中 · 剩余 \(remainingString(end: state.focusTimerEnd))")
                                    .monospacedDigit()
                            }
                        } action: { state.showEmergencyOverrideSheet = true }
                    }
                } else if state.isScheduledLockActive {
                    InfoBanner(style: .info, icon: "calendar.badge.clock", actionTitle: "紧急退出", actionColor: .focusDanger, actionDisabled: state.scheduledExitUsesThisMonth >= state.scheduledExitQuota) {
                        Text("定时屏蔽中 · 本月紧急退出剩余 \(max(0, state.scheduledExitQuota - state.scheduledExitUsesThisMonth))/\(state.scheduledExitQuota)")
                            .monospacedDigit()
                    } action: { state.showScheduledExitSheet = true }
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
                        Text("未设置屏蔽密码，停止屏蔽无需验证。建议设置，为冲动解除增加一道门槛。")
                    } action: { state.showSettingsSheet = true }
                }

                if let error = state.lastError {
                    InfoBanner(style: .danger, actionTitle: "清除", contentFont: .caption) {
                        Text(error)
                    } action: { state.lastError = nil }
                }
            }
            .padding(.horizontal)

            // Bottom control bar (full-width bar, bottom margin only)
            controlBar
                .padding(.top, 8)
                .padding(.bottom, 16)
        }
        .frame(minWidth: 500, minHeight: 500, alignment: .top)
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
            SettingsView(state: state)
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
        .alert("冷静期内无法解除屏蔽", isPresented: $state.showCooldownAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text("冷静期剩余 \(coolDownString(state.coolDownRemaining))，结束后才能停止屏蔽。")
            }
        }
    }

    private var passwordDialogTitle: String {
        switch state.pendingActionLabel {
        case "解除屏蔽": return "确认解除屏蔽"
        case "结束正计时": return "确认结束正计时"
        case "删除条目": return "确认删除条目"
        default: return "输入密码\(state.pendingActionLabel)"
        }
    }

    private var passwordDialogSubtitle: String {
        switch state.pendingActionLabel {
        case "解除屏蔽": return "解除后要做什么？先确认这是必要的。"
        case "结束正计时": return "提前结束会中断这次专注。"
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
            Image(systemName: state.blockingEnabled ? "lock.shield.fill" : "lock.shield")
                .font(.system(size: 20))
                .foregroundStyle(state.blockingEnabled ? Color.focusActive : Color.secondary)
                .frame(width: 24)

            if state.isProcessing {
                ProgressView().controlSize(.small)
                Text("处理中…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(state.blockingEnabled ? "屏蔽中" : "已停止")
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

            Button(action: { state.showSettingsSheet = true }) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(AlwaysActiveBorderlessStyle())
            .help("设置")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 56)
        .overlay(alignment: .top) { Divider() }
        .background(Color.secondary.opacity(0.07))
    }

    /// 延时屏蔽倒计时期间，主按钮变为「立即屏蔽」。
    private var controlButtonTitle: String {
        if state.delayedBlockActive { return "立即屏蔽" }
        return state.blockingEnabled ? "停止屏蔽" : "开启屏蔽"
    }

    private var controlButtonColor: Color {
        if state.delayedBlockActive { return .focusActive }
        return state.blockingEnabled ? .focusDanger : .focusAccent
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