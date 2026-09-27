import SwiftUI

struct FocusTimerView: View {
    @ObservedObject var state: AppState
    @State private var focusCustomMinutes: Int = 25
    @State private var delayedCustomMinutes: Int = 30
    @State private var focusGoal = ""
    @State private var delayedGoal = ""
    @State private var configKind: FocusTimerState.Kind = .focus
    @State private var focusMode: FocusMode = .countdown
    @State private var restEvent = ""

    private var restMinutesBinding: Binding<Int> {
        Binding(
            get: { state.restMinutes },
            set: { state.restMinutes = min(120, max(1, $0)) }
        )
    }

    private enum FocusMode { case countdown, elapsed, rest }

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
                        if state.restActive {
                            restRunningView
                        } else if state.focusTimerActive {
                            focusRunningView
                        } else if state.delayedBlockActive {
                            delayedBlockRunningView
                        } else if !state.blockingEnabled {
                            focusLockedNotice
                        } else {
                            focusConfigView
                        }
                    case .delayedBlock:
                        if state.restActive {
                            restRunningView
                        } else if state.delayedBlockActive {
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
    private var focusLockedNotice: some View {
        SectionCard(
            title: "专注计时需要先开启屏蔽",
            icon: "lock.shield",
            subtitle: "开启屏蔽后才能使用倒计时、正计时和休息。"
        ) {
            HStack {
                Spacer()
                Button {
                    state.toggleBlocking()
                } label: {
                    Label("开启屏蔽", systemImage: "lock.fill")
                        .padding(.vertical, 5)
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: .focusActive))
                .disabled(state.isProcessing)
                Spacer()
            }
        }
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

            // 模式：倒计时 / 正计时 / 休息（三者平行）
            Picker("模式", selection: $focusMode) {
                Text("倒计时").tag(FocusMode.countdown)
                Text("正计时").tag(FocusMode.elapsed)
                Text("休息").tag(FocusMode.rest)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            if focusMode == .countdown {
                presetAndCustomView(minutes: $focusCustomMinutes)

                goalInputCard(
                    title: "这次想专注完成什么？",
                    placeholder: "例如：完成报告第三章 · 阅读 30 页书",
                    hint: "开始计时后，它会悬浮在屏幕上方，提醒你别偏离。",
                    text: $focusGoal
                )
            } else if focusMode == .elapsed {
                VStack(alignment: .leading, spacing: 8) {
                    Text("正计时")
                        .font(.headline)
                    Text("开始后向上累计已用时，没有结束时间；结束时需输入密码，但不占用紧急退出次数。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("悬浮窗会一直显示已用时。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .focusCard()

                goalInputCard(
                    title: "这次想专注完成什么？",
                    placeholder: "例如：完成报告第三章 · 阅读 30 页书",
                    hint: "开始后悬浮窗会显示已用时，提醒你别偏离。",
                    text: $focusGoal
                )
            } else {
                restConfigCard
            }

            if !state.blockingEnabled {
                Text("屏蔽未开启，请先开启屏蔽再使用专注计时")
                    .font(.subheadline)
                    .foregroundStyle(Color.focusDanger)
                    .padding()
                    .background(Color.focusDanger.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            if focusMode == .countdown {
                Button {
                    state.startFocusTimer(minutes: focusCustomMinutes, goal: focusGoal)
                    focusGoal = ""
                } label: {
                    Label("开始计时", systemImage: "play.fill")
                        .padding(.vertical, 6)
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: .focusActive))
                .disabled(focusCustomMinutes < 1 || state.delayedBlockActive || !state.blockingEnabled)
            } else if focusMode == .elapsed {
                Button {
                    state.startFocusTimerElapsed(goal: focusGoal)
                    focusGoal = ""
                } label: {
                    Label("开始正计时", systemImage: "play.fill")
                        .padding(.vertical, 6)
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: .focusActive))
                .disabled(state.delayedBlockActive || !state.blockingEnabled || state.focusTimerActive)
            } else if focusMode == .rest {
                Button {
                    state.startRest(minutes: state.restMinutes, event: restEvent)
                    restEvent = ""
                } label: {
                    Label("开始休息", systemImage: "cup.and.saucer.fill")
                        .padding(.vertical, 6)
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
                .disabled(!state.blockingEnabled || state.focusTimerActive)
            }

            if focusMode == .countdown {
                focusOptionsCard
            } else if focusMode == .elapsed {
                elapsedOptionsCard
            } else if focusMode == .rest {
                restOptionsCard
            }
        }
        .padding()
    }

    @ViewBuilder
    private var elapsedOptionsCard: some View {
        SectionCard(title: "专注选项", icon: "switch.2", spacing: 4) {
            Toggle(isOn: Binding(
                get: { state.remindFocusTimerAfterEnd },
                set: { newValue in
                    state.setRemindFocusTimerAfterEnd(newValue)
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("结束时提醒开启下一轮")
                        .font(.subheadline)
                    Text("手动结束后会弹窗提醒开启下一轮")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    @ViewBuilder
    private var restConfigCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("休息", systemImage: "cup.and.saucer.fill")
                    .font(.headline)
                    .foregroundStyle(Color.focusAccent)
                Spacer()
                HStack(spacing: 6) {
                    DialogNumberField(number: restMinutesBinding, allowedRange: 1...120)
                        .frame(width: 54)
                    Text("分钟")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("休息期间不弹提醒，结束后再继续；休息事件会悬浮提醒。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !state.actionPrompts.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(state.actionPrompts.prefix(4)) { item in
                        Button {
                            restEvent = restEvent == item.text ? "" : item.text
                        } label: {
                            Text(item.text)
                                .font(.caption)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(
                                    restEvent == item.text
                                        ? Color.focusAccent.opacity(0.18)
                                        : Color.secondary.opacity(0.10),
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule().strokeBorder(
                                        restEvent == item.text
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

            DialogTextField(
                text: $restEvent,
                placeholder: "休息时想做什么？",
                height: 22
            )

        }
        .padding(12)
        .background(Color.focusAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var restOptionsCard: some View {
        SectionCard(title: "休息选项", icon: "switch.2", spacing: 4) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { state.restLockScreen },
                    set: { newValue in
                        state.setRestLockScreen(newValue)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("点击休息后锁屏")
                            .font(.subheadline)
                        Text("点击开始休息时立即锁定屏幕")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Divider()

                Toggle(isOn: Binding(
                    get: { state.remindRestManualEnd },
                    set: { newValue in
                        state.setRemindRestManualEnd(newValue)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("主动结束后提醒")
                            .font(.subheadline)
                        Text("手动结束休息后，也弹窗询问开启下一轮")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
        }
    }

    @ViewBuilder
    private var restRunningView: some View {
        VStack(spacing: 18) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.focusAccent)
            Text("休息中")
                .font(.title2.bold())
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(countdownString(at: context.date, end: state.restEnd))
                    .font(.system(size: 52, weight: .light, design: .monospaced))
                    .monospacedDigit()
            }
            if let goal = state.restGoal, !goal.isEmpty {
                goalDisplayCard(goal)
            }
            Text("休息结束后会提醒你继续")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                state.cancelRest()
            } label: {
                Label("结束休息", systemImage: "xmark")
                    .padding(.vertical, 6)
            }
            .buttonStyle(AlwaysActiveButtonStyle(color: .gray))
        }
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var delayedBlockConfigView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(Color.focusAccent)
            Text("延时屏蔽")
                .font(.title2.bold())
            Text("开始延时后自由浏览，倒计时结束自动开启屏蔽。")
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

                goalInputCard(
                    title: "这段时间想做什么？",
                    placeholder: "例如：查完这几篇资料 · 刷 20 分钟短视频到点停",
                    hint: "倒计时结束会自动屏蔽，这个安排会悬浮提醒你不要超时。",
                    text: $delayedGoal
                )

                Button {
                    state.startDelayedBlock(minutes: delayedCustomMinutes, goal: delayedGoal)
                    delayedGoal = ""
                } label: {
                    Label("开始延时", systemImage: "play.fill")
                        .padding(.vertical, 6)
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
                .disabled(delayedCustomMinutes < 1 || state.blockingEnabled || state.focusTimerActive)

                delayedBlockOptionsCard
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
            Text("剩余 \(max(0, state.scheduledExitQuota - state.scheduledExitUsesThisMonth)) 次 · 紧急退出只解除当前时间段锁定，屏蔽保持开启；其他时间段仍可编辑。")
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
        SectionCard(title: "延时选项", icon: "switch.2") {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { state.delayedBlockLockScreen },
                set: { newValue in
                    state.setDelayedBlockLockScreen(newValue)
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
                    state.setDelayedBlockAllowExtension($0)
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
        }
    }

    /// 专注计时页选项卡：悬浮窗是否显示倒计时 + 结束后提醒（原在设置里）。
    @ViewBuilder
    private var focusOptionsCard: some View {
        SectionCard(title: "专注选项", icon: "switch.2") {
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
                    state.setRemindFocusTimerAfterEnd($0)
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("结束时提醒开启下一轮")
                        .font(.subheadline)
                    Text("专注计时自然到点后，是否弹窗询问开启下一轮计时")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Divider()

            Toggle(isOn: Binding(
                get: { state.remindCountdownManualEnd },
                set: { newValue in
                    state.setRemindCountdownManualEnd(newValue)
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("主动结束后提醒")
                        .font(.subheadline)
                    Text("紧急退出倒计时后，也弹窗询问开启下一轮")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
        }
    }

    private func goalInputCard(title: String, placeholder: String, hint: String, text: Binding<String>) -> some View {
        SectionCard(title: title, icon: "target", spacing: 8) {
            TextField(placeholder, text: text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// A compact read-only chip showing the current session event/goal.
    private func goalDisplayCard(_ goal: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "target")
                .font(.subheadline)
                .foregroundStyle(Color.focusAccent)
            Text("事件")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(goal)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.focusAccent.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.focusAccent.opacity(0.25), lineWidth: 1))
        .frame(maxWidth: 360)
    }

    @ViewBuilder
    private func presetAndCustomView(minutes: Binding<Int>) -> some View {
        SectionCard(title: "时长设置", icon: "clock") {
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

            Text("选择预设，或输入 1–480 分钟。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        }
    }

    @ViewBuilder
    private var focusRunningView: some View {
        VStack(spacing: 18) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let progress = focusProgress(at: context.date)
                ZStack {
                    Circle()
                        .stroke(Color.focusActive.opacity(0.14), lineWidth: 10)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Color.focusActive,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.25), value: progress)

                    VStack(spacing: 6) {
                        Text(state.isElapsedFocus ? "正计时" : "剩余")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if state.isElapsedFocus {
                            Text(elapsedString(context.date))
                                .font(.system(size: 46, weight: .light, design: .monospaced))
                                .monospacedDigit()
                        } else {
                            Text(countdownString(at: context.date, end: state.focusTimerEnd))
                                .font(.system(size: 46, weight: .light, design: .monospaced))
                                .monospacedDigit()
                        }
                    }
                }
                .frame(width: 228, height: 228)
            }

            Text(state.isElapsedFocus ? "屏蔽设置已锁定 · 结束需密码" : "屏蔽设置已锁定")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let goal = state.focusTimerGoal, !goal.isEmpty {
                goalDisplayCard(goal)
            }

            VStack(spacing: 10) {
                if state.isElapsedFocus {
                    Text("结束不占用紧急退出次数")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        state.requestEndElapsedFocus()
                    } label: {
                        Label("结束正计时", systemImage: "xmark.shield")
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(AlwaysActiveButtonStyle(color: .focusDanger))
                } else {
                    Text("紧急退出剩余 \(max(0, state.emergencyQuota - state.emergencyUsesThisMonth)) 次")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        state.showEmergencyOverrideSheet = true
                    } label: {
                        Label("紧急退出", systemImage: "xmark.shield")
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(AlwaysActiveButtonStyle(color: .focusDanger))
                    .disabled(state.emergencyUsesThisMonth >= state.emergencyQuota)
                }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 18)
    }

    private func focusProgress(at date: Date) -> Double {
        // Elapsed focus has no target duration; show an empty ring instead of pretending it completed.
        guard !state.isElapsedFocus,
              let start = state.focusCountdownStart,
              let end = state.focusTimerEnd else {
            return 0
        }

        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 1 }

        let elapsed = date.timeIntervalSince(start)
        return min(1, max(0, elapsed / total))
    }

    /// 正计时已用时（HH:MM:SS）。
    private func elapsedString(_ now: Date) -> String {
        guard let start = state.focusTimerStart else { return "00:00" }
        let total = max(0, Int(now.timeIntervalSince(start)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
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
