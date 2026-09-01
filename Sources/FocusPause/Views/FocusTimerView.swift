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
                } else {
                    // 分段栏始终显示，便于在专注/延时/定时之间切换查看（运行时也能看到其它板块）。
                    configPicker
                    switch configKind {
                    case .focus:
                        if state.focusTimerActive {
                            focusRunningView
                        } else {
                            focusConfigView
                        }
                    case .delayedBlock:
                        if state.delayedBlockActive {
                            delayedBlockRunningView
                        } else {
                            delayedBlockConfigView
                        }
                    case .scheduledBlock:
                        scheduledBlockConfigView
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
                .init(value: FocusTimerState.Kind.scheduledBlock, label: "定时屏蔽", icon: "calendar.badge.clock"),
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

            focusOptionsCard

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

                delayedBlockOptionsCard

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

    // MARK: - 定时屏蔽（每天重复的多段时间段）

    @ViewBuilder
    private var scheduledBlockConfigView: some View {
        VStack(spacing: 16) {
            // 有任一时间段激活时：顶部显示屏蔽中横幅，下方仍可编辑其他时间段。
            if state.isScheduledLockActive {
                scheduledActiveBanner
            }
            scheduledBlockSetupView
        }
    }

    @ViewBuilder
    private var scheduledBlockSetupView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 40))
                .foregroundStyle(Color.focusAccent)
            Text("定时屏蔽")
                .font(.title2.bold())
            Text("设置几段时间段，勾选「生效」才启用；任一时段内点停止需紧急退出（密码）。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Toggle(isOn: Binding(
                get: { state.forceBlockAll },
                set: { state.setForceBlockAll($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("强制屏蔽名单中的全部网站与 App")
                        .font(.subheadline)
                    Text("开启后，即使某条规则已关闭也会一并屏蔽（仅作用于已添加的条目）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 10)

            VStack(spacing: 12) {
                Text("时间段（每天重复 / 一次性）")
                    .font(.headline)
                if state.scheduledWindows.isEmpty {
                    Text("还没有时间段。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(state.scheduledWindows.enumerated()), id: \.element.id) { index, window in
                    scheduledWindowRow(index, window)
                }

                Button {
                    // 默认给一个「从现在起 1 小时后开始」的窗口，避免一新增就落在当前时刻立即触发屏蔽。
                    let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
                    let nowMinute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                    let start = (nowMinute + 60) % 1440
                    state.addScheduledWindow(startMinute: start, endMinute: (start + 120) % 1440)
                } label: {
                    Label("新增时间段", systemImage: "plus")
                        .padding(.vertical, 4)
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
                .fixedSize()

                Text("结束时间早于开始视为跨到次日（如 22:00–02:00）；新加的默认未生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .focusCard()

            VStack(spacing: 6) {
                Text("紧急退出（提前结束）需密码，每月最多 \(state.scheduledExitQuota) 次")
                    .font(.subheadline)
                Text("当前在某时间段内时会自动开启屏蔽。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .focusCard()
        }
        .padding()
    }

    @ViewBuilder
    private var scheduledActiveBanner: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(Color.focusAccent)
                Text("定时屏蔽中 · 至 \(activeWindowEndLabel)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack {
                Spacer()
                Button {
                    state.showScheduledExitSheet = true
                } label: {
                    Label("紧急退出", systemImage: "xmark.shield")
                        .padding(.vertical, 5)
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: .focusDanger))
                .disabled(state.scheduledExitUsesThisMonth >= state.scheduledExitQuota)
                Spacer()
            }
            Text("剩余 \(max(0, state.scheduledExitQuota - state.scheduledExitUsesThisMonth)) 次 · 紧急退出只解除本次硬锁，屏蔽保持；其他时间段仍可编辑。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .focusCard()
    }

    /// 当前激活时间段的结束时刻文案（跨午夜标注次日）。
    private var activeWindowEndLabel: String {
        guard let id = state.activeScheduledWindowID,
              let w = state.scheduledWindows.first(where: { $0.id == id }) else { return "" }
        let h = w.endMinute / 60
        let m = w.endMinute % 60
        let overnight = w.endMinute < w.startMinute
        return String(format: "%02d:%02d%@", h, m, overnight ? "（次日）" : "")
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return min(1439, (c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    private func minuteDate(_ minute: Int) -> Date {
        Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(minute * 60))
    }

    /// 时间段行的开始/结束 DatePicker 绑定，就地改分钟并写回。
    private func minuteBinding(for index: Int, isStart: Bool) -> Binding<Date> {
        Binding(
            get: {
                guard index < state.scheduledWindows.count else { return Date() }
                let m = isStart ? state.scheduledWindows[index].startMinute : state.scheduledWindows[index].endMinute
                return minuteDate(m)
            },
            set: { newValue in
                guard index < state.scheduledWindows.count else { return }
                var updated = state.scheduledWindows
                if isStart { updated[index].startMinute = minuteOfDay(newValue) }
                else { updated[index].endMinute = minuteOfDay(newValue) }
                state.setScheduledWindows(updated)
            }
        )
    }

    private func scheduledWindowRow(_ index: Int, _ window: ScheduledWindow) -> some View {
        // 当前正在屏蔽的时间段锁定不可编辑，其他时间段可自由修改。
        // 当前正被屏蔽（硬锁中）的时间段，其生效开关锁定不可关，避免绕过密码退出。
        let isActive = state.isScheduledLockActive && state.activeScheduledWindowID == window.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: enabledBinding(for: index)) {
                    Text("生效").font(.subheadline)
                }
                .toggleStyle(.switch)
                .disabled(isActive)

                Picker("类型", selection: repeatsBinding(for: index)) {
                    Text("每天重复").tag(true)
                    Text("一次性").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                .disabled(isActive)

                if isActive {
                    Text("屏蔽中")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.focusDanger)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.focusDanger.opacity(0.12), in: Capsule())
                } else if !state.isScheduledLockActive {
                    Spacer()
                }
                if !isActive {
                    Button {
                        state.removeScheduledWindow(id: window.id)
                    } label: {
                        Image(systemName: "trash").foregroundStyle(Color.focusDanger)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !window.repeats {
                HStack {
                    Text("日期").font(.subheadline).foregroundStyle(.secondary)
                    DatePicker("日期", selection: anchorDayBinding(for: index), displayedComponents: [.date])
                        .labelsHidden()
                        .disabled(isActive)
                }
            }

            HStack(spacing: 8) {
                Text("开始").font(.subheadline).foregroundStyle(.secondary)
                DatePicker("开始", selection: minuteBinding(for: index, isStart: true), displayedComponents: [.hourAndMinute])
                    .labelsHidden()
                    .disabled(isActive)
                Text("至").font(.subheadline).foregroundStyle(.secondary)
                DatePicker("结束", selection: minuteBinding(for: index, isStart: false), displayedComponents: [.hourAndMinute])
                    .labelsHidden()
                    .disabled(isActive)
                Spacer()
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func enabledBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { index < state.scheduledWindows.count && state.scheduledWindows[index].enabled },
            set: { newValue in
                guard index < state.scheduledWindows.count else { return }
                var updated = state.scheduledWindows
                updated[index].enabled = newValue
                state.setScheduledWindows(updated)
            }
        )
    }

    private func repeatsBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { index < state.scheduledWindows.count && state.scheduledWindows[index].repeats },
            set: { newValue in
                guard index < state.scheduledWindows.count else { return }
                var updated = state.scheduledWindows
                updated[index].repeats = newValue
                if !newValue && updated[index].anchorDay == nil {
                    updated[index].anchorDay = defaultOneTimeDay(for: updated[index])
                }
                state.setScheduledWindows(updated)
            }
        )
    }

    private func anchorDayBinding(for index: Int) -> Binding<Date> {
        Binding(
            get: { index < state.scheduledWindows.count ? (state.scheduledWindows[index].anchorDay ?? Date()) : Date() },
            set: { newValue in
                guard index < state.scheduledWindows.count else { return }
                var updated = state.scheduledWindows
                updated[index].anchorDay = Calendar.current.startOfDay(for: newValue)
                state.setScheduledWindows(updated)
            }
        )
    }

    /// 切到一次性时默认从明天开始，避免选到今天马上触发屏蔽。
    private func defaultOneTimeDay(for w: ScheduledWindow) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))
            ?? Calendar.current.startOfDay(for: Date())
    }

    // MARK: - 游动到页面上的设置开关

    /// 延时屏蔽页：到期锁屏 / 允许延长（原在设置里）。
    @ViewBuilder
    private var delayedBlockOptionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { state.delayedBlockLockScreen },
                set: { newValue in
                    state.delayedBlockLockScreen = newValue
                    UserDefaults.standard.set(newValue, forKey: "delayedBlockLockScreen")
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("到期后锁屏")
                        .font(.subheadline)
                    Text("延时屏蔽结束后自动锁定屏幕")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Divider()

            Toggle(isOn: Binding(
                get: { state.delayedBlockAllowExtension },
                set: {
                    state.delayedBlockAllowExtension = $0
                    UserDefaults.standard.set($0, forKey: "delayedBlockAllowExtension")
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("允许延长")
                        .font(.subheadline)
                    Text("到期时提供「再等 5/10 分钟」选项，最多 1 次")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
        .focusCard()
    }

    /// 专注计时页选项卡：悬浮窗是否显示倒计时 + 结束后提醒（原在设置里）。
    @ViewBuilder
    private var focusOptionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { state.focusOverlayShowsTime },
                set: { state.setFocusOverlayShowsTime($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("悬浮窗显示剩余倒计时")
                        .font(.subheadline)
                    Text("专注计时时，屏幕上方常驻悬浮窗是否显示剩余时间")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Divider()

            Toggle(isOn: Binding(
                get: { state.remindFocusTimerAfterEnd },
                set: {
                    state.remindFocusTimerAfterEnd = $0
                    UserDefaults.standard.set($0, forKey: "remindFocusTimerAfterEnd")
                    if !$0 { state.stopFocusEndReminder() }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("结束时提醒开启下一轮")
                        .font(.subheadline)
                    Text("专注计时结束后，是否弹窗询问开启下一轮计时")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
        .focusCard()
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
                Text("本月紧急退出剩余 \(max(0, state.emergencyQuota - state.emergencyUsesThisMonth)) 次")
                    .font(.subheadline)
                Text("紧急退出需输入密码，且每月最多 \(state.emergencyQuota) 次")
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
            .disabled(state.emergencyUsesThisMonth >= state.emergencyQuota)
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
