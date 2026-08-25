import SwiftUI

struct FocusTimerView: View {
    @ObservedObject var state: AppState
    @State private var focusCustomMinutes: Int = 25
    @State private var delayedCustomMinutes: Int = 30
    @State private var focusGoal = ""
    @State private var delayedGoal = ""
    @State private var configKind: FocusTimerState.Kind = .focus

    private let presets = [25, 30, 60]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if state.delayedBlockPendingAuth {
                    delayedBlockPendingView
                } else if let kind = state.activeTimerKind {
                    if kind == .focus {
                        focusRunningView
                    } else {
                        delayedBlockRunningView
                    }
                } else {
                    configPicker
                    if configKind == .focus {
                        focusConfigView
                    } else {
                        delayedBlockConfigView
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var configPicker: some View {
        SubSegmentCard(
            options: [
                .init(value: FocusTimerState.Kind.focus, label: "专注计时", icon: "timer"),
                .init(value: FocusTimerState.Kind.delayedBlock, label: "延时屏蔽", icon: "clock"),
            ],
            selection: $configKind
        )
    }

    @ViewBuilder
    private var focusConfigView: some View {
        VStack(spacing: 16) {
            Image(systemName: "timer")
                .font(.system(size: 40))
                .foregroundStyle(Color.focusAccent)
            Text("专注计时")
                .font(.title2.bold())
            Text("开始计时后，所有屏蔽设置将被锁定，计时结束或紧急退出后才能修改。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            presetAndCustomView(minutes: $focusCustomMinutes)
                .focusCard()

            goalInputCard(
                title: "这次想专注完成什么？",
                placeholder: "例如：完成报告第三章 · 阅读 30 页书",
                hint: "开始计时后，它会悬浮在屏幕上方，提醒你别偏离。",
                text: $focusGoal
            )

            if !state.blockingEnabled {
                Text("屏蔽未开启，请先开启屏蔽再使用专注计时")
                    .font(.subheadline)
                    .foregroundStyle(Color.focusDanger)
                    .padding()
                    .background(Color.focusDanger.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            Button {
                state.startFocusTimer(minutes: focusCustomMinutes, goal: focusGoal)
                focusGoal = ""
            } label: {
                Label("开始计时", systemImage: "play.fill")
                    .padding(.vertical, 6)
            }
            .buttonStyle(AlwaysActiveButtonStyle(color: .focusActive))
            .disabled(focusCustomMinutes < 1 || state.delayedBlockActive || !state.blockingEnabled)
        }
        .padding()
    }

    @ViewBuilder
    private var delayedBlockConfigView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(Color.focusAccent)
            Text("延时屏蔽")
                .font(.title2.bold())
            Text("开始计时后自由浏览，倒计时结束自动开启屏蔽。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if state.blockingEnabled {
                Text("屏蔽已开启，无需延时屏蔽")
                    .font(.subheadline)
                    .foregroundStyle(Color.focusDanger)
                    .padding()
                    .background(Color.focusDanger.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            } else {
                presetAndCustomView(minutes: $delayedCustomMinutes)
                    .focusCard()

                goalInputCard(
                    title: "这段时间想做什么？",
                    placeholder: "例如：查完这几篇资料 · 刷 20 分钟短视频到点停",
                    hint: "倒计时结束会自动屏蔽，这个安排会悬浮提醒你不要超时。",
                    text: $delayedGoal
                )

                Text("到期锁屏、延长等选项见「设置 → 延时屏蔽」")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    state.startDelayedBlock(minutes: delayedCustomMinutes, goal: delayedGoal)
                    delayedGoal = ""
                } label: {
                    Label("开始计时", systemImage: "play.fill")
                        .padding(.vertical, 6)
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
                .disabled(delayedCustomMinutes < 1 || state.blockingEnabled || state.focusTimerActive)
            }
        }
        .padding()
    }

    private func goalInputCard(title: String, placeholder: String, hint: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            TextField(placeholder, text: text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .focusCard()
    }

    /// A compact read-only card showing the current session goal/plan.
    private func goalDisplayCard(_ goal: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "target").foregroundStyle(Color.focusAccent)
            Text("本次目标：\(goal)")
                .font(.subheadline)
                .multilineTextAlignment(.leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.focusAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func presetAndCustomView(minutes: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("预设时长")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { preset in
                    Button {
                        minutes.wrappedValue = preset
                    } label: {
                        Text("\(preset) 分钟")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(AlwaysActiveButtonStyle(
                        color: selectedPreset(for: minutes.wrappedValue) == preset ? .blue : .gray))
                }
            }

            Text("自定义")
                .font(.headline)
            HStack {
                Stepper(value: minutes, in: 1...480, step: 5) {
                    TextField("分钟", value: minutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var focusRunningView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.focusActive)
            Text("专注计时中")
                .font(.title2.bold())
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(countdownString(at: context.date, end: state.focusTimerEnd))
                    .font(.system(size: 56, weight: .light, design: .monospaced))
                    .monospacedDigit()
            }
            Text("所有屏蔽设置已锁定")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let goal = state.focusTimerGoal, !goal.isEmpty {
                goalDisplayCard(goal)
            }

            VStack(spacing: 6) {
                Text("本月紧急退出剩余 \(max(0, AppState.monthlyEmergencyQuota - state.emergencyUsesThisMonth)) 次")
                    .font(.subheadline)
                Text("紧急退出需输入密码，且每月最多 \(AppState.monthlyEmergencyQuota) 次")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .focusCard()

            Button {
                state.showEmergencyOverrideSheet = true
            } label: {
                Label("紧急退出", systemImage: "xmark.shield")
                    .padding(.vertical, 6)
            }
            .buttonStyle(AlwaysActiveButtonStyle(color: .focusDanger))
            .disabled(state.emergencyUsesThisMonth >= AppState.monthlyEmergencyQuota)
        }
        .padding()
    }

    @ViewBuilder
    private var delayedBlockRunningView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(Color.focusAccent)
            Text("延时屏蔽倒计时")
                .font(.title2.bold())
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(countdownString(at: context.date, end: state.delayedBlockEnd))
                    .font(.system(size: 56, weight: .light, design: .monospaced))
                    .monospacedDigit()
            }
            Text("倒计时结束后将自动开启屏蔽")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let goal = state.delayedBlockGoal, !goal.isEmpty {
                goalDisplayCard(goal)
            }

            VStack(spacing: 8) {
                Button {
                    state.blockNow()
                } label: {
                    Label("立即屏蔽", systemImage: "lock.fill")
                        .padding(.vertical, 6)
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: .focusActive))

                Button {
                    state.cancelDelayedBlock()
                } label: {
                    Label("取消计时", systemImage: "xmark")
                        .padding(.vertical, 6)
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: .gray))
            }
        }
        .padding()
    }

    @ViewBuilder
    private var delayedBlockPendingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.focusDanger)
            Text("屏蔽未生效")
                .font(.title2.bold())
            Text("到点未成功开启屏蔽")
                .font(.caption)
                .foregroundStyle(.secondary)

            if state.delayedBlockRetryCount < 1 {
                Text("还可延长 1 次")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("延长次数已用完")
                    .font(.subheadline)
                    .foregroundStyle(Color.focusDanger)
            }

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                if let next = state.delayedBlockNextRetryAt, next > Date() {
                    Text("弹窗将在 \(Int(next.timeIntervalSinceNow))s 后再次出现")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text("弹窗即将出现…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.focusDanger.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            Button {
                state.presentExtendAlert()
            } label: {
                Label("立即打开弹窗", systemImage: "exclamationmark.bubble")
                    .padding(.vertical, 6)
            }
            .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
        }
        .padding()
    }

    private func selectedPreset(for minutes: Int) -> Int? {
        presets.first { $0 == minutes }
    }

    private func countdownString(at now: Date, end: Date?) -> String {
        guard let end, end > now else { return "00:00" }
        let remaining = Int(end.timeIntervalSince(now))
        let mins = remaining / 60
        let secs = remaining % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
