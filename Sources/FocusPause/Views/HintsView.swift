import SwiftUI

/// 「一些提示」页，两分区：
/// - 文字提示：只在当前页以浮动卡片展示，不进弹窗；点卡片可编辑。
/// - 一些提醒：展示在提醒弹窗里（纯展示），行内可编辑/删除/排序。
/// 新增提示/提醒直接进入编辑框。
struct HintsView: View {
    @ObservedObject var state: AppState
    @State private var editing: EditingItem?
    @State private var draft = ""
    @FocusState private var draftFocus: Bool
    /// 鼠标悬停的提醒条目 id：悬停到该行时才显示其操作按钮。
    @State private var hoveringPromptID: UUID?

    private struct EditingItem: Identifiable {
        let id = UUID()
        let promptID: UUID?   // nil = 新增
        let kind: PromptItem.Kind
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 先「一些提醒」（会出现在弹窗里的行动项），再「文字提示」（陪伴语）。
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("一些提醒")
                    Text("前 4 条会作为休息事项，出现在提醒弹窗里；其余仅用于编辑排序。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if state.actionPrompts.isEmpty {
                        emptyState(
                            "bell.badge",
                            "还没有提醒。",
                            "新增后，前 4 条会作为休息事项，出现在提醒弹窗里。"
                        )
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0) {
                        ForEach(Array(state.actionPrompts.enumerated()), id: \.element.id) { index, prompt in
                            actionCell(prompt, isRestItem: index < 4)
                        }
                    }
                    .focusList()
                    addButton("新增提醒") {
                        beginNew(kind: .action)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("文字提示")
                    Text("添加一些能警醒自己的句子；它们会作为陪伴语，出现在练习页与提醒弹窗的底部。点击即可编辑。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if state.textPrompts.isEmpty {
                        emptyState(
                            "quote.bubble",
                            "还没有文字提示。",
                            "写下能让自己停下来的那句话，点击下方新增。"
                        )
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(state.textPrompts) { item in
                                card(item)
                            }
                        }
                        .focusCard()
                    }
                    addButton("新增文字提示") {
                        beginNew(kind: .text)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
            .padding()
        }
        .sheet(item: $editing, onDismiss: { draft = "" }) { item in
            editSheet(item)
        }
    }

    // MARK: - 文字提示卡片

    private func card(_ item: PromptItem) -> some View {
        Button {
            beginEdit(item)
        } label: {
            Text(item.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.surfaceWell, in: RoundedRectangle(cornerRadius: FocusRadius.control, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: FocusRadius.control))
        }
        .buttonStyle(.plain)
    }


    // MARK: - 一些提醒行

    /// 单个提醒小卡片：文案与操作按钮同行。两列网格里的一个格子。
    private func actionCell(_ prompt: PromptItem, isRestItem: Bool) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: isRestItem ? "cup.and.saucer.fill" : "arrow.up.right.circle")
                    .foregroundStyle(isRestItem ? Color.focusAccent : Color.secondary)
                Text(prompt.text)
                    .font(.subheadline)
                    .lineLimit(1)
                // 前 4 条会作为休息事项出现在提醒弹窗里，给一个明确的标识。
                if isRestItem {
                    Text("休息事项")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.focusAccent.opacity(0.14), in: Capsule())
                        .foregroundStyle(Color.focusAccent)
                        .fixedSize()
                }
            }

            Spacer(minLength: 8)

            RowActionButtons(
                revealed: hoveringPromptID == prompt.id,
                onEdit: { beginEdit(prompt) },
                moveUp: { state.movePrompt(id: prompt.id, up: true) },
                canMoveUp: state.actionPrompts.first?.id != prompt.id,
                onDelete: { state.deletePrompt(id: prompt.id) }
            )
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.surfaceHairline).frame(height: 1)
        }
        .onHover { inside in
            hoveringPromptID = inside ? prompt.id : (hoveringPromptID == prompt.id ? nil : hoveringPromptID)
        }
    }



    // MARK: - 编辑 sheet（新增 / 编辑共用）

    private func editSheet(_ item: EditingItem) -> some View {
        VStack(spacing: 16) {
            Text(item.promptID == nil ? "新增提示" : "编辑提示")
                .font(.headline)
            TextField("写下内容", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focusField()
                .frame(width: 260)
                .focused($draftFocus)
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                if item.promptID != nil {
                    Button {
                        state.deletePrompt(id: item.promptID!)
                        editing = nil
                    } label: {
                        Text("删除")
                    }
                    .buttonStyle(AlwaysActiveTintedButtonStyle())
                }
                Button("取消") { editing = nil }
                    .buttonStyle(AlwaysActiveTintedButtonStyle())
                Button("保存") { save(item) }
                    .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            DispatchQueue.main.async { draftFocus = true }
        }
    }

    private func save(_ item: EditingItem) {
        if let promptID = item.promptID {
            state.updatePrompt(id: promptID, text: draft)
        } else {
            state.addPrompt(text: draft, kind: item.kind)
        }
        editing = nil
    }

    private func beginEdit(_ prompt: PromptItem) {
        draft = prompt.text
        editing = EditingItem(promptID: prompt.id, kind: prompt.kind)
    }

    private func beginNew(kind: PromptItem.Kind) {
        draft = ""
        editing = EditingItem(promptID: nil, kind: kind)
    }

    // MARK: - 通用

    @ViewBuilder
    private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Button(action: action) {
                Label(title, systemImage: "plus")
                    .font(.subheadline)
                    .padding(.vertical, 4)
            }
            .buttonStyle(AlwaysActiveTintedButtonStyle(color: .focusAccent))
            .fixedSize()
            Spacer()
        }
    }

    @ViewBuilder
    private func emptyState(_ icon: String, _ text: String, _ hint: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.headline)
    }
}
