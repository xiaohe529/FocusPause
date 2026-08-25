import SwiftUI

struct AppListView: View {
    @ObservedObject var state: AppState
    @State private var newApp = ""
    @State private var pickerApps: [String]? = nil
    @State private var revertingRuleID: UUID? = nil
    @State private var pendingDeleteID: UUID? = nil

    var appRules: [BlockRule] {
        state.blockRules.filter { $0.type == .app }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Input row
            HStack {
                TextField("输入 App 精确名称，如「微信」「Google Chrome」", text: $newApp)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addApp() }
                Button("添加", action: addApp)
                    .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
                    .disabled(newApp.trimmingCharacters(in: .whitespaces).isEmpty)
                Button(action: loadInstalledApps) {
                    Label("选择", systemImage: "list.bullet")
                        .font(.body)
                }
                .buttonStyle(AlwaysActiveBorderlessStyle(color: .focusAccent))
                .help("从已安装 App 中选择")
            }
            Text("屏蔽开启后，这些 App 会被强制关闭。")
                .font(.caption).foregroundStyle(.secondary)

            Divider()

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
                }
            }
        }
        .sheet(item: Binding(
            get: { pickerApps.map { AppPickerItem(apps: $0) } },
            set: { if $0 == nil { pickerApps = nil } }
        )) { item in
            VStack(spacing: 12) {
                HStack {
                    Text("选择要屏蔽的 App")
                        .font(.headline)
                    Spacer()
                    Text("\(item.apps.count) 个")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if item.apps.isEmpty {
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
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                            ForEach(item.apps, id: \.self) { appName in
                                Button(appName) {
                                    addFromPicker(appName)
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .frame(minHeight: 250)
                }
                HStack {
                    Spacer()
                    Button("关闭") { pickerApps = nil }
                }
            }
            .padding()
            .frame(width: 500, height: 420)
        }
        .alert("删除条目？", isPresented: Binding(
            get: { pendingDeleteID != nil },
            set: { if !$0 { pendingDeleteID = nil } }
        )) {
            Button("取消", role: .cancel) { pendingDeleteID = nil }
            Button("删除", role: .destructive) {
                if let id = pendingDeleteID {
                    let rule = state.blockRules.first { $0.id == id }
                    state.blockRules.removeAll { $0.id == id }
                    pendingDeleteID = nil
                    if let rule { FocusLogger.info("Deleted app rule: \(rule.name)") }
                    Task { _ = await state.save() }
                }
            }
        } message: {
            if let id = pendingDeleteID, let r = state.blockRules.first(where: { $0.id == id }) {
                Text("确定要删除「\(r.name)」吗？此操作不可撤销。")
            } else {
                Text("确定要删除这条规则吗？")
            }
        }
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
                if let lockedError = state.ruleListLockedError() {
                    state.lastError = lockedError
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
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
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
                    state.lastError = state.blockingEnabled ? "屏蔽开启中，名单已锁定，无法关闭规则" : "专注计时中，无法解除屏蔽规则"
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
        Divider()
            .padding(.leading, 28)
    }

    @ViewBuilder
    private func appIcon(for name: String) -> some View {
        Image(systemName: "app.badge")
            .foregroundStyle(.secondary)
    }

    func addApp() {
        let clean = newApp.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty,
              !state.blockRules.contains(where: { $0.name == clean && $0.type == .app })
        else { return }
        state.blockRules.append(BlockRule(name: clean, type: .app))
        Task { _ = await state.save() }
        newApp = ""
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
        var names: Set<String> = []
        var diagnostics: [String] = []

        let dirs = [
            "/Applications",
            "/System/Applications",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        ]

        // Strategy 1: FileManager.contentsOfDirectory
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

        // Strategy 2: ls fallback if FileManager returned nothing
        if names.isEmpty {
            for dir in dirs {
                let apps = listAppNamesViaLS(in: dir)
                if apps.isEmpty {
                    diagnostics.append("ls \(dir): empty or failed")
                } else {
                    for a in apps where !a.isEmpty { names.insert(a) }
                }
            }
        }

        let exclusions = Set(["FocusPause", "Finder", "System Settings", "System Preferences", "登录窗口"])
        let filtered = names.filter { !exclusions.contains($0) }.sorted()

        FocusLogger.info("loadInstalledApps: found \(filtered.count) apps; diagnostics: \(diagnostics.isEmpty ? "none" : diagnostics.joined(separator: " | "))")

        if filtered.isEmpty && !diagnostics.isEmpty {
            state.lastError = "应用枚举失败：\(diagnostics.prefix(3).joined(separator: " | "))"
        }
        pickerApps = filtered
    }

    private func listAppNamesViaLS(in dir: String) -> [String] {
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

private struct AppPickerItem: Identifiable {
    let id = UUID()
    let apps: [String]
}
