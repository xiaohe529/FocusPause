import SwiftUI

enum UnlockField: Hashable {
    case password
}

struct MainView: View {
    @ObservedObject var state: AppState
    @State private var passwordInput = ""
    @State private var passwordError = false
    @State private var emergencyPasswordInput = ""
    @State private var emergencyPasswordError = false
    @State private var scheduledExitPasswordInput = ""
    @State private var scheduledExitPasswordError = false
    @FocusState private var unlockFocus: UnlockField?
    @FocusState private var emergencyFocus: Bool
    @FocusState private var scheduledExitFocus: Bool

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

            // Status banners (low-key, for focus-timer / delayed-block states)
            if state.focusTimerActive {
                if state.isElapsedFocus {
                    statusBanner(
                        icon: "lock.fill",
                        color: .focusActive,
                        actionTitle: "结束",
                        actionColor: .focusDanger,
                        actionDisabled: false,
                        action: { state.requestEndElapsedFocus() }
                    ) {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("正计时中 · 已用时 \(elapsedString(context.date, start: state.focusTimerStart))")
                                .font(.subheadline)
                                .monospacedDigit()
                        }
                    }
                } else {
                    statusBanner(
                        icon: "lock.fill",
                        color: .focusActive,
                        actionTitle: "紧急退出",
                        actionColor: .focusDanger,
                        actionDisabled: state.emergencyUsesThisMonth >= state.emergencyQuota,
                        action: { state.showEmergencyOverrideSheet = true }
                    ) {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text("专注计时中 · 剩余 \(remainingString(end: state.focusTimerEnd))")
                                .font(.subheadline)
                                .monospacedDigit()
                        }
                    }
                }
            } else if state.isScheduledLockActive {
                statusBanner(
                    icon: "calendar.badge.clock",
                    color: .focusAccent,
                    actionTitle: "紧急退出",
                    actionColor: .focusDanger,
                    actionDisabled: state.scheduledExitUsesThisMonth >= state.scheduledExitQuota,
                    action: { state.showScheduledExitSheet = true }
                ) {
                    Text("定时屏蔽中 · 本月紧急退出剩余 \(max(0, state.scheduledExitQuota - state.scheduledExitUsesThisMonth))/\(state.scheduledExitQuota)")
                        .font(.subheadline)
                        .monospacedDigit()
                }
            } else if state.delayedBlockPendingAuth {
                statusBanner(
                    icon: "exclamationmark.triangle.fill",
                    color: .focusDanger,
                    actionTitle: "去授权",
                    actionColor: .focusDanger,
                    actionDisabled: false,
                    action: { state.selectedTab = 1 }
                ) {
                    Text("屏蔽未生效 · 到点未授权")
                        .font(.subheadline)
                }
            } else if state.delayedBlockActive {
                statusBanner(
                    icon: "clock.badge.exclamationmark",
                    color: .focusAccent,
                    actionTitle: nil,
                    actionColor: nil,
                    actionDisabled: false,
                    action: {}
                ) {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("延时屏蔽倒计时 · 剩余 \(remainingString(end: state.delayedBlockEnd)) · 到点自动屏蔽")
                            .font(.subheadline)
                            .monospacedDigit()
                    }
                }
            } else if !state.scheduledWindows.isEmpty {
                statusBanner(
                    icon: "calendar.badge.exclamationmark",
                    color: .focusAccent,
                    actionTitle: nil,
                    actionColor: nil,
                    actionDisabled: false,
                    action: {}
                ) {
                    Text("已设定 \(state.scheduledWindows.filter(\.enabled).count)/\(state.scheduledWindows.count) 段定时屏蔽")
                        .font(.subheadline)
                        .monospacedDigit()
                }
            }

            // Password not set reminder (low-key)
            if state.blockingEnabled && !state.hasPassword {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill").foregroundStyle(Color.focusDanger)
                    Text("未设置屏蔽密码，停止屏蔽无需验证。建议设置，为冲动解除增加一道门槛。")
                        .font(.caption)
                        .foregroundStyle(Color.focusDanger)
                    Spacer()
                    Button("设置") { state.showSettingsSheet = true }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Color.focusDanger)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.focusDanger.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal)
                .padding(.top, 8)
            }

            // Error banner (low-key)
            if let error = state.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.focusDanger)
                    Text(error).font(.caption).foregroundStyle(Color.focusDanger)
                    Spacer()
                    Button("清除") { state.lastError = nil }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Color.focusDanger)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.focusDanger.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal)
                .padding(.top, 8)
            }

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
                VStack(spacing: 16) {
                    Text("输入密码\(state.pendingActionLabel)")
                        .font(.headline)
                    SecureField("输入密码", text: $passwordInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .focused($unlockFocus, equals: .password)
                        .onSubmit { verifyPassword() }
                    if passwordError {
                        Text("密码错误").foregroundStyle(.red).font(.caption)
                    }
                    HStack(spacing: 16) {
                        Button("取消") {
                            state.showPasswordSheet = false
                            passwordInput = ""
                            passwordError = false
                            state.pendingToggleAction = nil
                            state.pendingActionLabel = ""
                            state.lastError = nil
                        }
                        Button("确认") { verifyPassword() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .frame(width: 300, height: 180)
                .onAppear {
                    DispatchQueue.main.async {
                        unlockFocus = .password
                    }
                }
            }
        .sheet(isPresented: $state.showSettingsSheet) {
            SettingsView(state: state)
        }
        .sheet(isPresented: $state.showEmergencyOverrideSheet, onDismiss: {
                emergencyPasswordInput = ""
                emergencyPasswordError = false
            }) {
                VStack(spacing: 16) {
                    Text("紧急退出专注计时")
                        .font(.headline)
                    Text("本月已用 \(state.emergencyUsesThisMonth) / \(state.emergencyQuota) 次")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("输入密码", text: $emergencyPasswordInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .focused($emergencyFocus)
                        .onSubmit { confirmEmergencyOverride() }
                    if emergencyPasswordError {
                        Text(state.lastError ?? "密码错误")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    HStack(spacing: 16) {
                        Button("取消") {
                            state.showEmergencyOverrideSheet = false
                            emergencyPasswordInput = ""
                            emergencyPasswordError = false
                        }
                        Button("确认") { confirmEmergencyOverride() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .frame(width: 320, height: 240)
                .onAppear {
                    DispatchQueue.main.async { emergencyFocus = true }
                }
            }
        .sheet(isPresented: $state.showScheduledExitSheet, onDismiss: {
                scheduledExitPasswordInput = ""
                scheduledExitPasswordError = false
            }) {
                VStack(spacing: 16) {
                    Text("紧急退出定时屏蔽")
                        .font(.headline)
                    Text("本月已用 \(state.scheduledExitUsesThisMonth) / \(state.scheduledExitQuota) 次（与专注计时独立）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("输入密码", text: $scheduledExitPasswordInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .focused($scheduledExitFocus)
                        .onSubmit { confirmScheduledExit() }
                    if scheduledExitPasswordError {
                        Text(state.lastError ?? "密码错误")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    HStack(spacing: 16) {
                        Button("取消") {
                            state.showScheduledExitSheet = false
                            scheduledExitPasswordInput = ""
                            scheduledExitPasswordError = false
                        }
                        Button("确认") { confirmScheduledExit() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .frame(width: 320, height: 240)
                .onAppear {
                    DispatchQueue.main.async { scheduledExitFocus = true }
                }
            }
        .alert("冷静期内无法解除屏蔽", isPresented: $state.showCooldownAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text("冷静期剩余 \(coolDownString(state.coolDownRemaining))，结束后才能停止屏蔽。")
            }
        }
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

    @ViewBuilder
    private func statusBanner<Content: View>(
        icon: String,
        color: Color,
        actionTitle: String?,
        actionColor: Color?,
        actionDisabled: Bool,
        action: @escaping () -> Void,
        @ViewBuilder text: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            text()
            Spacer()
            if let actionTitle, let actionColor {
                Button(actionTitle) { action() }
                    .buttonStyle(AlwaysActiveBorderlessStyle(color: actionColor))
                    .font(.caption)
                    .disabled(actionDisabled)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal)
        .padding(.top, 8)
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