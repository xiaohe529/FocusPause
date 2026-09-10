import SwiftUI
import FocusPauseHelperShared

struct WebsiteListView: View {
    @ObservedObject var state: AppState
    @State private var newDomain = ""
    @State private var revertingRuleID: UUID? = nil
    @State private var pendingDeleteID: UUID? = nil
    @State private var showCacheInfo = false

    let suggestions = ["facebook.com","twitter.com","youtube.com","reddit.com","instagram.com","tiktok.com","linkedin.com","bilibili.com","douyin.com","weibo.com"]

    var filteredSuggestions: [String] {
        suggestions.filter { s in
            !state.blockRules.contains(where: { $0.name == s && $0.type == .website })
        }
    }

    var websiteRules: [BlockRule] {
        state.blockRules.filter { $0.type == .website }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Input row
            HStack {
                TextField("输入域名，如 weibo.com", text: $newDomain)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addDomain() }
                Button("添加", action: addDomain)
                    .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
                    .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Text("屏蔽开启后，名单中的网站会被拦截，无法访问。")
                .font(.caption).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showCacheInfo.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showCacheInfo ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                        Label("屏蔽后已打开的网站有时还能访问？", systemImage: "info.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.focusAccent)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showCacheInfo {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("网站屏蔽依赖系统 hosts 文件，但浏览器会缓存 DNS 并保持已建立的连接，所以屏蔽刚开启时，已打开的页面或紧接着的刷新可能仍能打开。稍等片刻或重启浏览器即可生效。")
                        Text("小技巧：用一个专门的浏览器（如 Chrome、Edge）访问想屏蔽的网站，并把它加入「App 屏蔽」名单。屏蔽开启（含延时屏蔽到期）时该浏览器会被强制退出，网站自然打不开。")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .focusCard()
                    .padding(.top, 6)
                }
            }

            // Quick add pills — clearly labeled as suggestions, not the current list
            if !filteredSuggestions.isEmpty {
                Text("推荐屏蔽网站（点击添加）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(filteredSuggestions, id: \.self) { s in
                            Button(s) {
                                addSuggestion(s)
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }

            if !state.invalidWebsiteRules.isEmpty {
                InfoBanner(style: .warning, icon: "exclamationmark.triangle") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("以下网站规则无效，不会参与屏蔽，请删除后重新添加：")
                        ForEach(state.invalidWebsiteRules) { rule in
                            Text("· \(rule.name)")
                        }
                    }
                }
            }

            Divider()

            // Rule list
            if websiteRules.isEmpty {
                emptyView
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach($state.blockRules) { $rule in
                            if rule.type == .website {
                                ruleRow($rule)
                            }
                        }
                    }
                }
            }
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
                    if let rule { FocusLogger.info("Deleted website rule: \(rule.name)") }
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
            Image(systemName: "globe.badge.xmark")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("还没有添加网站")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Text("输入域名或点击上方推荐屏蔽网站快速添加")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxHeight: 200)
    }

    @ViewBuilder
    private func ruleRow(_ rule: Binding<BlockRule>) -> some View {
        let r = rule.wrappedValue
        HStack {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
                .frame(width: 20)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: rule.enabled.wrappedValue) { oldValue, newState in
            // Skip if this change is a revert from a failed/cancelled operation
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
                // Enabling (OFF→ON): no FocusPause password, save directly
                Task {
                    let success = await state.save()
                    if !success {
                        // Admin dialog cancelled — revert to OFF
                        revertingRuleID = ruleID
                        rule.enabled.wrappedValue = oldValue
                    }
                }
            }
        }
    }

    func addDomain() {
        let clean = newDomain.trimmingCharacters(in: .whitespaces)
        guard let domain = DomainNormalizer.normalize(clean) else {
            state.lastError = "请输入有效域名，例如 weibo.com"
            return
        }
        guard !state.blockRules.contains(where: { $0.name == domain && $0.type == .website }) else {
            newDomain = ""
            return
        }
        state.blockRules.append(BlockRule(name: domain, type: .website))
        Task { _ = await state.save() }
        state.lastError = nil
        newDomain = ""
    }

    func addSuggestion(_ s: String) {
        guard let domain = DomainNormalizer.normalize(s) else { return }
        guard !state.blockRules.contains(where: { $0.name == domain && $0.type == .website })
        else { return }
        state.blockRules.append(BlockRule(name: domain, type: .website))
        Task { _ = await state.save() }
    }
}
