import SwiftUI

struct AppListView: View {
    @ObservedObject var state: AppState
    @State private var showAppPicker = false
    @State private var isLoadingApps = false
    @State private var pickerApps: [String]? = nil
    @State private var revertingRuleID: UUID? = nil
    @State private var pendingDeleteID: UUID? = nil
    /// App 搜索关键字（App 是固定的，搜索后点击即添加，避免手打不准）。
    @State private var searchQuery = ""

    var appRules: [BlockRule] {
        state.blockRules.filter { $0.type == .app }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 搜索框：App 是固定的，从已安装列表里搜、点一下就添加，避免手打不准。
            // 右侧保留「选择」按钮，打开完整列表挑选，两种入口并存。
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("搜索 App，如「微信」「Chrome」", text: $searchQuery)
                            .textFieldStyle(.plain)
                            .onSubmit { addFirstSearchResult() }
                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: FocusRadius.control, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: FocusRadius.control, style: .continuous)
                            .strokeBorder(Color.surfaceHairline, lineWidth: 1)
                    )

                    Button {
                        showAppPicker = true
                        loadInstalledApps()
                    } label: {
                        Label("选择", systemImage: "list.bullet")
                    }
                    .buttonStyle(AlwaysActiveTintedButtonStyle(color: .focusAccent))
                    .help("从已安装 App 中挑选")
                }

                Text("屏蔽开启后，这些 App 会被强制关闭。")
                    .font(.caption).foregroundStyle(.secondary)

                // 搜索结果：只在输入关键字时出现，避免与下方名单板块视觉重复。
                if isLoadingApps {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在读取已安装 App…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    if searchResults.isEmpty {
                        Text("没有找到匹配的 App。")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(searchResults, id: \.self) { app in
                                    searchResultRow(app)
                                }
                            }
                            .focusList()
                        }
                        .frame(maxHeight: 220)
                    }
                }
            }

            // App list
            if appRules.isEmpty {
                emptyView
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach($state.blockRules) { $rule in
                            if rule.type == .app {
                                appRow($rule)
                            }
                        }
                    }
                    .focusList()
                }
            }
        }
        .onAppear {
            if pickerApps == nil { loadInstalledApps() }
        }
        .sheet(isPresented: $showAppPicker) {
            VStack(spacing: 12) {
                HStack {
                    Text("选择要屏蔽的 App")
                        .font(.headline)
                    Spacer()
                    if let apps = pickerApps, !isLoadingApps {
                        Text("\(apps.count) 个")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("点击右侧「＋」加入屏蔽名单；已在名单中的会显示为已添加。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(height: 0)
                    .onAppear { if pickerApps == nil { loadInstalledApps() } }

                if isLoadingApps {
                    Spacer()
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("正在读取已安装 App…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else if let apps = pickerApps {
                    if apps.isEmpty {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 32))
                                .foregroundStyle(.tertiary)
                            Text("未找到已安装应用")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                            Text("请手动输入 App 名称添加")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                                ForEach(apps, id: \.self) { appName in
                                    let added = state.blockRules.contains { $0.name == appName && $0.type == .app }
                                    Button {
                                        if !added { addFromPicker(appName) }
                                    } label: {
                                        HStack(spacing: 8) {
                                            appIcon(for: appName)
                                                .frame(width: 20, height: 20)
                                            Text(appName)
                                                .font(.subheadline)
                                                .lineLimit(1)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            if added {
                                                Text("已添加")
                                                    .font(.caption2)
                                                    .foregroundStyle(.tertiary)
                                            } else {
                                                Image(systemName: "plus.circle")
                                                    .foregroundStyle(Color.focusAccent)
                                            }
                                        }
                                        .padding(.vertical, 7)
                                        .padding(.horizontal, 8)
                                        .focusRow()
                                        .contentShape(Rectangle())
                                        .opacity(added ? 0.5 : 1)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(added)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .frame(minHeight: 250)
                    }
                }
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    Button("取消") { showAppPicker = false }
                        .buttonStyle(AlwaysActiveTintedButtonStyle())
                    Button("完成") { showAppPicker = false }
                        .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
                }
            }
            .padding()
            .frame(width: 520, height: 440)
        }
        // 与其余弹窗统一：自绘 ConfirmDialogView（原来用系统 .alert，按钮配色不一致）。
        .sheet(isPresented: Binding(
            get: { pendingDeleteID != nil },
            set: { if !$0 { pendingDeleteID = nil } }
        )) {
            ConfirmDialogView(
                title: "删除条目？",
                icon: "trash",
                tint: .focusDanger,
                message: pendingDeleteMessage,
                confirmTitle: "删除",
                confirmTint: .focusDanger
            ) {
                if let id = pendingDeleteID {
                    let rule = state.blockRules.first { $0.id == id }
                    state.blockRules.removeAll { $0.id == id }
                    pendingDeleteID = nil
                    if let rule { FocusLogger.info("Deleted app rule: \(rule.name)") }
                    Task { _ = await state.save() }
                }
            } onCancel: {
                pendingDeleteID = nil
            }
        }
    }

    private var pendingDeleteMessage: String {
        if let id = pendingDeleteID, let r = state.blockRules.first(where: { $0.id == id }) {
            return "确定要删除「\(r.name)」吗？此操作不可撤销。"
        }
        return "确定要删除这条规则吗？"
    }

    /// 过滤后的已安装 App（排除已添加的）。
    private var searchResults: [String] {
        guard let apps = pickerApps else { return [] }
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let already = Set(appRules.map { $0.name.lowercased() })
        return apps
            .filter { !already.contains($0.lowercased()) }
            .filter { q.isEmpty || $0.lowercased().contains(q) }
            .sorted()
    }

    @ViewBuilder
    private func searchResultRow(_ appName: String) -> some View {
        Button {
            addFromPicker(appName)
        } label: {
            HStack(spacing: 8) {
                appIcon(for: appName)
                    .frame(width: 20, height: 20)
                Text(appName)
                    .font(.subheadline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "plus.circle")
                    .foregroundStyle(Color.focusAccent)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .focusRow()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addFirstSearchResult() {
        if let first = searchResults.first { addFromPicker(first) }
    }

    @ViewBuilder
    private var emptyView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "app.badge.xmark")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("还没有添加 App")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Text("输入 App 名称或点击「选择」从已安装 App 中挑选")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxHeight: 200)
    }

    @ViewBuilder
    private func appRow(_ rule: Binding<BlockRule>) -> some View {
        let r = rule.wrappedValue
        HStack {
            appIcon(for: r.name)
                .frame(width: 20, height: 20)
            Toggle(isOn: rule.enabled) {
                Text(r.name)
                    .font(.body)
                    .lineLimit(1)
            }
            .toggleStyle(AlwaysActiveSwitchStyle())
            Spacer()
            Button {
                if state.ruleListLockedError() != nil {
                    state.presentRuleListLockedNotice()
                    return
                }
                if state.hasPassword {
                    let ruleID = r.id
                    state.pendingActionLabel = "删除条目"
                    state.pendingToggleAction = {
                        pendingDeleteID = ruleID
                    }
                    state.showPasswordSheet = true
                } else {
                    pendingDeleteID = r.id
                }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.tertiary)
                    .padding(4)
            }
            .buttonStyle(AlwaysActiveBorderlessStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .focusRow(cornerRadius: FocusRadius.card)
        .onChange(of: rule.enabled.wrappedValue) { oldValue, newState in
            if revertingRuleID == r.id {
                revertingRuleID = nil
                return
            }

            let ruleID = r.id

            if !newState {
                // Disabling: blocked during focus timer or while blocking is active
                if state.isLocked || state.blockingEnabled {
                    revertingRuleID = ruleID
                    rule.enabled.wrappedValue = oldValue
                    state.presentRuleListLockedNotice()
                    return
                }
                // Disabling (ON→OFF): allowed without password when not blocking
                Task {
                    let success = await state.save()
                    if !success {
                        revertingRuleID = ruleID
                        rule.enabled.wrappedValue = oldValue
                    }
                }
            } else {
                Task {
                    let success = await state.save()
                    if !success {
                        revertingRuleID = ruleID
                        rule.enabled.wrappedValue = oldValue
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func appIcon(for name: String) -> some View {
        let homeApps = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/\(name).app").path
        let candidates = [
            "/Applications/\(name).app",
            "/System/Applications/\(name).app",
            homeApps
        ]
        let path = candidates.first { FileManager.default.fileExists(atPath: $0) }
        if let path {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "app.badge")
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
        }
    }

    func addFromPicker(_ appName: String) {
        guard !state.blockRules.contains(where: { $0.name == appName && $0.type == .app }) else { return }
        state.blockRules.append(BlockRule(name: appName, type: .app))
        Task { _ = await state.save() }
        if var arr = pickerApps { arr.removeAll { $0 == appName }; pickerApps = arr }
    }

    func remove(_ rule: BlockRule) {
        guard !state.isLocked else { return }
        state.blockRules.removeAll { $0.id == rule.id }
        Task { _ = await state.save() }
    }

    func loadInstalledApps() {
        guard !isLoadingApps else { return }
        isLoadingApps = true
        pickerApps = nil

        Task.detached(priority: .userInitiated) {
            let result = Self.scanInstalledApps()
            await MainActor.run {
                pickerApps = result.apps
                isLoadingApps = false
                if !result.diagnostics.isEmpty && result.apps.isEmpty {
                    state.lastError = "应用枚举失败：\(result.diagnostics.prefix(3).joined(separator: " | "))"
                }
            }
        }
    }

    private struct AppScanResult {
        let apps: [String]
        let diagnostics: [String]
    }

    nonisolated private static func scanInstalledApps() -> AppScanResult {
        var names: Set<String> = []
        var diagnostics: [String] = []

        let dirs = [
            "/Applications",
            "/System/Applications",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        ]

        for dir in dirs {
            do {
                let items = try FileManager.default.contentsOfDirectory(atPath: dir)
                for item in items where item.hasSuffix(".app") {
                    let clean = item.replacingOccurrences(of: ".app", with: "")
                    if !clean.isEmpty { names.insert(clean) }
                }
            } catch {
                diagnostics.append("FM \(dir): \(error.localizedDescription)")
            }
        }

        if names.isEmpty {
            for dir in dirs {
                let apps = listAppNamesViaLS(in: dir)
                if apps.isEmpty {
                    diagnostics.append("ls \(dir): empty or failed")
                } else {
                    for app in apps where !app.isEmpty { names.insert(app) }
                }
            }
        }

        // 这里按**目录里的文件名**匹配。bundle 文件名现在是 `Focus&Pause.app`，
        // 但老版本装出来的是 `FocusPause.app`，两个名字都要排除。
        let exclusions = Set(["FocusPause", "Focus&Pause", "Finder", "System Settings", "System Preferences", "登录窗口"])
        let filtered = names.filter { !exclusions.contains($0) }.sorted()
        FocusLogger.info("Installed app scan: found \(filtered.count) apps")
        return AppScanResult(apps: filtered, diagnostics: diagnostics)
    }

    private nonisolated static func listAppNamesViaLS(in dir: String) -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ls")
        task.arguments = ["-1", dir]
        let out = Pipe()
        let err = Pipe()
        task.standardOutput = out
        task.standardError = err
        do {
            try task.run()
            task.waitUntilExit()
            let output = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return output.components(separatedBy: "\n")
                .filter { $0.hasSuffix(".app") }
                .map { $0.replacingOccurrences(of: ".app", with: "") }
        } catch {
            return []
        }
    }
}
