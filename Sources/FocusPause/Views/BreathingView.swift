import SwiftUI

/// 「我的工具箱」页：分组的可编辑外链集合，分组名和链接都可增删改。
struct BreathingView: View {
    @ObservedObject var state: AppState

    @State private var editing: EditTarget?
    @State private var renamingGroup: RenameTarget?
    @State private var draftTitle = ""
    @State private var draftURL = ""
    @State private var draftGroupName = ""
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
                    Text("还没有分组。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
                    .fixedSize()
                    Spacer()
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
            .padding()
        }
        .sheet(item: $editing, onDismiss: { draftTitle = ""; draftURL = "" }) { item in
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
                Text("还没有链接。")
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
            .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
            .fixedSize()
        }
        .focusCard()
    }

    /// 单个链接小卡片：文案与操作按钮同行。两列网格里的一个格子。
    private func linkCell(group: ToolboxGroup, link: ToolboxLink) -> some View {
        HStack(spacing: 8) {
            Link(destination: URL(string: link.url) ?? URL(string: "https://")!) {
                Label(link.title, systemImage: "arrow.up.right.square")
                    .font(.subheadline)
            }
            .foregroundStyle(Color.focusAccent)
            .lineLimit(1)

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
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .onHover { inside in
            hoveringLinkID = inside ? link.id : (hoveringLinkID == link.id ? nil : hoveringLinkID)
        }
    }

    // MARK: - 链接编辑 sheet

    private func linkSheet(_ item: EditTarget) -> some View {
        VStack(spacing: 16) {
            Text(item.linkID == nil ? "新增链接" : "编辑链接")
                .font(.headline)
            TextField("文案（如：去暂停工具箱）", text: $draftTitle)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .focused($titleFocus)
            TextField("链接地址", text: $draftURL)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            HStack(spacing: 16) {
                Button("取消") { editing = nil }
                if item.linkID != nil {
                    Button("删除", role: .destructive) {
                        state.deleteToolboxLink(groupID: item.groupID, linkID: item.linkID!)
                        editing = nil
                    }
                }
                Button("保存") {
                    saveLink(item)
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || draftURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 340)
        .onAppear {
            DispatchQueue.main.async { titleFocus = true }
        }
    }

    private func saveLink(_ item: EditTarget) {
        if let linkID = item.linkID {
            state.updateToolboxLink(linkID: linkID, title: draftTitle, url: draftURL)
        } else {
            state.addToolboxLink(groupID: item.groupID, title: draftTitle, url: draftURL)
        }
        editing = nil
    }

    // MARK: - 分组重命名 sheet

    private func renameSheet(_ item: RenameTarget) -> some View {
        VStack(spacing: 16) {
            Text(item.isNew ? "新增分组" : "分组名称")
                .font(.headline)
            TextField("分组名", text: $draftGroupName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .focused($titleFocus)
            HStack(spacing: 16) {
                Button("取消") { renamingGroup = nil }
                Button("保存") {
                    if let groupID = item.groupID {
                        state.renameToolboxGroup(id: groupID, name: draftGroupName)
                    } else {
                        state.addToolboxGroup(name: draftGroupName)
                    }
                    renamingGroup = nil
                }
                .buttonStyle(.borderedProminent)
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
        editing = EditTarget(groupID: groupID, linkID: link.id)
    }

    private func beginNewLink(in groupID: UUID) {
        draftTitle = ""
        draftURL = ""
        editing = EditTarget(groupID: groupID, linkID: nil)
    }
}
