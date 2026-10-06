import SwiftUI
import FocusPauseHelperShared

struct WebsiteListView: View {
    @ObservedObject var state: AppState
    @State private var newDomain = ""
    @State private var revertingRuleID: UUID? = nil
    @State private var pendingDeleteID: UUID? = nil
    @State private var showCacheInfo = false

    /// 常见站点库（含国内常见站点），用于输入时给补全建议，防止手输错误。
    private static let knownDomains: [String] = [
        "google.com", "youtube.com", "facebook.com", "instagram.com", "twitter.com", "x.com",
        "tiktok.com", "reddit.com", "linkedin.com", "netflix.com", "twitch.tv", "pinterest.com",
        "discord.com", "telegram.org", "whatsapp.com", "snapchat.com", "tumblr.com", "quora.com",
        "medium.com", "stackoverflow.com", "github.com", "gitlab.com", "notion.so", "figma.com",
        "zhihu.com", "weibo.com", "douyin.com", "bilibili.com", "xiaohongshu.com", "douban.com",
        "toutiao.com", "kuaishou.com", "hupu.com", "tieba.baidu.com", "baidu.com",
        "taobao.com", "jd.com", "pinduoduo.com", "tmall.com", "qq.com", "163.com", "sina.com.cn",
        "youku.com", "iqiyi.com", "sohu.com", "ifeng.com", "csdn.net", "jianshu.com", "zhihu.com",
        "163.com", "1688.com", "xiaomi.com", "huawei.com", "apple.com", "microsoft.com",
    ]

    /// 输入时给出的补全建议（不含已添加的），最多 6 条。
    private var domainSuggestions: [String] {
        let q = newDomain.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let already = Set(state.blockRules.filter { $0.type == .website }.map { $0.name.lowercased() })
        let pool = Array(Set(Self.knownDomains)).sorted()
        return pool
            .filter { !already.contains($0) }
            .filter { $0.contains(q) && $0 != q }
            .sorted { a, b in
                // 前缀匹配优先
                let ap = a.hasPrefix(q), bp = b.hasPrefix(q)
                if ap != bp { return ap }
                return a < b
            }
            .prefix(6)
            .map { $0 }
    }

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
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    // 与 App 搜索框同一套自绘样式：聚焦时不变色，保持中性。
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                            .foregroundStyle(.secondary)
                        TextField("输入域名，如 weibo.com", text: $newDomain)
                            .textFieldStyle(.plain)
                            .onSubmit { addDomain() }
                        if !newDomain.isEmpty {
                            Button {
                                newDomain = ""
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

                    Button("添加", action: addDomain)
                        .buttonStyle(AlwaysActiveTintedButtonStyle(color: .focusAccent))
                        .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                // 输入未完成时给出补全建议；点一下只填进输入框，不直接加入名单，
                // 让用户在点「添加」前还能改一改。
                if !domainSuggestions.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(domainSuggestions, id: \.self) { domain in
                            Button {
                                newDomain = domain
                            } label: {
                                Text(domain)
                                    .font(.caption)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .focusChip()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
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
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("为什么还能访问？")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("网站屏蔽依赖系统 hosts 文件，但浏览器会缓存 DNS 并保持已建立的连接，所以刚开启屏蔽时，已打开的页面或紧接着的刷新可能仍能打开。稍等片刻或重启浏览器即可生效。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("小技巧")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("用一个专门的浏览器（如 Chrome、Edge）访问想屏蔽的网站，并把它加入「App 屏蔽」名单。屏蔽开启（含延时屏蔽到期）时该浏览器会被强制退出，网站自然打不开。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focusCard()
                    .padding(.top, 6)
                }
            }

            // 推荐网站：点一下填入输入框，再点「添加」才加入名单。
            if !filteredSuggestions.isEmpty {
                Text("推荐屏蔽网站（点击填入输入框）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(filteredSuggestions, id: \.self) { s in
                            Button(s) {
                                newDomain = s
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .focusChip()
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

            // Rule list
            if websiteRules.isEmpty {
                emptyView
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach($state.blockRules) { $rule in
                            if rule.type == .website {
                                ruleRow($rule)
                            }
                        }
                    }
                    .focusList()
                }
            }
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
                    if let rule { FocusLogger.info("Deleted website rule: \(rule.name)") }
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
            Text("输入域名，或点击上方推荐网站填入输入框后添加")
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

}
