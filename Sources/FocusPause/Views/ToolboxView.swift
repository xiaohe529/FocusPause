import SwiftUI
import AppKit

/// 「我的工具箱」页：分组的可编辑外链集合，分组名和链接都可增删改。
/// 注意：真正的呼吸练习在 PauseView 的新页面实现，本文件只承载工具箱。
struct ToolboxView: View {
    @ObservedObject var state: AppState

    @State private var editing: EditTarget?
    @State private var renamingGroup: RenameTarget?
    @State private var draftTitle = ""
    @State private var draftURL = ""
    @State private var draftGroupName = ""
    @State private var draftKind: ToolboxLink.Kind = .link
    @State private var showAppPicker = false
    @State private var appChoices: [(name: String, path: String)] = []
    @FocusState private var titleFocus: Bool
    /// 鼠标悬停的条目 id：悬停到该行时才显示其操作按钮，避免满屏图标眼花。
    @State private var hoveringGroupID: UUID?
    @State private var hoveringLinkID: UUID?

    private struct EditTarget: Identifiable {
        let id = UUID()
        let groupID: UUID
        let linkID: UUID?   // nil = 新增
    }

    private struct RenameTarget: Identifiable {
        let id = UUID()
        let groupID: UUID?   // nil = 新增分组
        var isNew: Bool { groupID == nil }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("把自己常用的练习入口放在这里，分组和链接都可增删改。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if state.toolboxGroups.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("添加第一个分组")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("把常用的练习入口放进来，支持网页外链和本机应用。")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }

                ForEach(state.toolboxGroups) { group in
                    groupSection(group)
                }

                HStack {
                    Button {
                        beginNewGroup()
                    } label: {
                        Label("新增分组", systemImage: "folder.badge.plus")
                            .font(.subheadline)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(AlwaysActiveTintedButtonStyle(color: .focusAccent))
                    .fixedSize()
                    Spacer()
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
            .padding()
        }
        .sheet(item: $editing, onDismiss: { draftTitle = ""; draftURL = ""; draftKind = .link; showAppPicker = false }) { item in
            linkSheet(item)
        }
        .sheet(item: $renamingGroup, onDismiss: { draftGroupName = "" }) { item in
            renameSheet(item)
        }
    }

    // MARK: - 分组版块

    private func groupSection(_ group: ToolboxGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(group.name)
                    .font(.headline)
                RowActionButtons(
                    revealed: hoveringGroupID == group.id,
                    onEdit: { beginRename(group) },
                    onDelete: { state.deleteToolboxGroup(id: group.id) }
                )
                Spacer()
            }
            .onHover { inside in
                hoveringGroupID = inside ? group.id : (hoveringGroupID == group.id ? nil : hoveringGroupID)
            }

            if group.links.isEmpty {
                Text("分组还是空的，点击下方「新增链接」添加。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                ForEach(group.links) { link in
                    linkCell(group: group, link: link)
                }
            }

            Button {
                beginNewLink(in: group.id)
            } label: {
                Label("新增链接", systemImage: "plus")
                    .font(.subheadline)
                    .padding(.vertical, 3)
            }
            .buttonStyle(AlwaysActiveTintedButtonStyle(color: .focusAccent))
            .fixedSize()
        }
        .focusCard()
    }

    /// 单个入口小卡片：文案与操作按钮同行。网页外链 / 本机应用。
    private func linkCell(group: ToolboxGroup, link: ToolboxLink) -> some View {
        HStack(spacing: 8) {
            if link.kind == .app {
                Button {
                    state.openToolboxItem(link)
                } label: {
                    HStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: link.url))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(link.title)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.focusAccent)
                .help("启动 \(link.url)")
            } else {
                Link(destination: URL(string: link.url) ?? URL(string: "https://")!) {
                    Label(link.title, systemImage: "arrow.up.right.square")
                        .font(.subheadline)
                }
                .foregroundStyle(Color.focusAccent)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            RowActionButtons(
                revealed: hoveringLinkID == link.id,
                onEdit: { beginEditLink(in: group.id, link: link) },
                moveUp: { state.moveToolboxLink(groupID: group.id, linkID: link.id, up: true) },
                canMoveUp: group.links.first?.id != link.id,
                onDelete: { state.deleteToolboxLink(groupID: group.id, linkID: link.id) }
            )
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusRow()
        .onHover { inside in
            hoveringLinkID = inside ? link.id : (hoveringLinkID == link.id ? nil : hoveringLinkID)
        }
    }

    // MARK: - 链接编辑 sheet

    private func linkSheet(_ item: EditTarget) -> some View {
        VStack(spacing: 16) {
            Text(item.linkID == nil ? "新增条目" : "编辑条目")
                .font(.headline)

            MiniSegmented(
                options: [(ToolboxLink.Kind.link, "网站链接"), (ToolboxLink.Kind.app, "本机应用")],
                selection: $draftKind
            )
            .frame(width: 240)

            TextField("名称（如：去暂停工具箱 / 日历）", text: $draftTitle)
                .textFieldStyle(.plain)
                .focusField()
                .frame(width: 280)
                .focused($titleFocus)

            if draftKind == .app {
                TextField("应用路径（如 /Applications/…/….app）", text: $draftURL)
                    .textFieldStyle(.plain)
                    .focusField()
                    .frame(width: 280)
                Button {
                    showAppPicker = true
                } label: {
                    Label("从已安装 App 中选择", systemImage: "list.bullet")
                        .font(.subheadline)
                }
                .buttonStyle(AlwaysActiveTintedButtonStyle(color: .focusAccent))
                .fixedSize()
            } else {
                TextField("链接地址", text: $draftURL)
                    .textFieldStyle(.plain)
                    .focusField()
                    .frame(width: 280)
            }

            HStack(spacing: 16) {
                Spacer(minLength: 0)
                if item.linkID != nil {
                    Button {
                        state.deleteToolboxLink(groupID: item.groupID, linkID: item.linkID!)
                        editing = nil
                    } label: {
                        Text("删除")
                    }
                    .buttonStyle(AlwaysActiveTintedButtonStyle())
                }
                Button("取消") { editing = nil }
                    .buttonStyle(AlwaysActiveTintedButtonStyle())
                Button("保存") { saveLink(item) }
                    .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
                    .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || draftURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
        .onAppear {
            DispatchQueue.main.async { titleFocus = true }
        }
        // 挂在编辑 sheet 内部（子 sheet），这样能在当前已弹出的编辑框之上再弹一层。
        .sheet(isPresented: $showAppPicker, onDismiss: { appChoices = [] }) {
            appPickerSheet
        }
    }

    /// 已安装 App 选择器：多在编辑 sheet 之上展示，内容在出现后异步加载。
    private var appPickerSheet: some View {
        VStack(spacing: 12) {
            HStack {
                Text("选择要启动的 App")
                    .font(.headline)
                Spacer()
                Text("\(appChoices.count) 个")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if appChoices.isEmpty {
                Spacer()
                ProgressView()
                Text("正在读取已安装应用…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(appChoices, id: \.path) { app in
                            Button {
                                draftTitle = app.name
                                draftURL = app.path
                                showAppPicker = false
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "app.badge")
                                        .foregroundStyle(Color.focusAccent)
                                    Text(app.name)
                                        .foregroundStyle(.primary)
                                    Text(app.path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 8)
                                .focusRow()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("关闭") { showAppPicker = false }
            }
        }
        .padding()
        .frame(width: 420, height: 420)
        .task {
            // 在 sheet 出现后再去枚举，避免「点一下就弹、第一次因状态未就绪而不出」的问题。
            if appChoices.isEmpty {
                appChoices = InstalledApps.installed()
            }
        }
    }

    private func saveLink(_ item: EditTarget) {
        if let linkID = item.linkID {
            state.updateToolboxLink(linkID: linkID, title: draftTitle, url: draftURL, kind: draftKind)
        } else {
            state.addToolboxLink(groupID: item.groupID, title: draftTitle, url: draftURL, kind: draftKind)
        }
        editing = nil
    }

    // MARK: - 分组重命名 sheet

    private func renameSheet(_ item: RenameTarget) -> some View {
        VStack(spacing: 16) {
            Text(item.isNew ? "新增分组" : "分组名称")
                .font(.headline)
            TextField("分组名", text: $draftGroupName)
                .textFieldStyle(.plain)
                .focusField()
                .frame(width: 220)
                .focused($titleFocus)
            HStack(spacing: 10) {
                Spacer(minLength: 8)
                Button("取消") { renamingGroup = nil }
                    .buttonStyle(AlwaysActiveTintedButtonStyle())
                Button("保存") {
                    if let groupID = item.groupID {
                        state.renameToolboxGroup(id: groupID, name: draftGroupName)
                    } else {
                        state.addToolboxGroup(name: draftGroupName)
                    }
                    renamingGroup = nil
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
                .disabled(draftGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            DispatchQueue.main.async { titleFocus = true }
        }
    }

    private func beginNewGroup() {
        draftGroupName = ""
        renamingGroup = RenameTarget(groupID: nil)
    }

    private func beginRename(_ group: ToolboxGroup) {
        draftGroupName = group.name
        renamingGroup = RenameTarget(groupID: group.id)
    }

    private func beginEditLink(in groupID: UUID, link: ToolboxLink) {
        draftTitle = link.title
        draftURL = link.url
        draftKind = link.kind
        editing = EditTarget(groupID: groupID, linkID: link.id)
    }

    private func beginNewLink(in groupID: UUID) {
        draftTitle = ""
        draftURL = ""
        draftKind = .link
        editing = EditTarget(groupID: groupID, linkID: nil)
    }
}
