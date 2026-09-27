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
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("文字提示")
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
                    }
                    addButton("新增文字提示") {
                        beginNew(kind: .text)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("一些提醒")
                    Text("前 4 条会出现在提醒弹窗里，其余仅用于编辑排序。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if state.actionPrompts.isEmpty {
                        emptyState(
                            "bell.badge",
                            "还没有提醒。",
                            "新增后，前 4 条会出现在提醒弹窗里。"
                        )
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                        ForEach(state.actionPrompts) { prompt in
                            actionCell(prompt)
                        }
                    }
                    addButton("新增提醒") {
                        beginNew(kind: .action)
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
                .background(cardColor(for: item), in: RoundedRectangle(cornerRadius: FocusRadius.control))
                .contentShape(RoundedRectangle(cornerRadius: FocusRadius.control))
        }
        .buttonStyle(.plain)
    }

    private func cardColor(for item: PromptItem) -> Color {
        Color.focusAccent.opacity(0.10)
    }

    // MARK: - 一些提醒行

    /// 单个提醒小卡片：文案与操作按钮同行。两列网格里的一个格子。
    private func actionCell(_ prompt: PromptItem) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right.circle")
                    .foregroundStyle(Color.focusAccent)
                Text(prompt.text)
                    .font(.subheadline)
                    .lineLimit(1)
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
        .background(actionColor(for: prompt), in: RoundedRectangle(cornerRadius: FocusRadius.control))
        .onHover { inside in
            hoveringPromptID = inside ? prompt.id : (hoveringPromptID == prompt.id ? nil : hoveringPromptID)
        }
    }

    private func actionColor(for prompt: PromptItem) -> Color {
        guard let index = state.actionPrompts.firstIndex(where: { $0.id == prompt.id }) else {
            return Color.secondary.opacity(0.06)
        }
        // 前 4 条是弹窗里会展示的，用主色高亮；其余保持中性。
        guard index < 4 else { return Color.secondary.opacity(0.06) }
        return Color.focusAccent.opacity(0.10)
    }

    // MARK: - 编辑 sheet（新增 / 编辑共用）

    private func editSheet(_ item: EditingItem) -> some View {
        VStack(spacing: 16) {
            Text(item.promptID == nil ? "新增提示" : "编辑提示")
                .font(.headline)
            TextField("写下内容", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .frame(width: 260)
                .focused($draftFocus)
            HStack(spacing: 16) {
                Button("取消") { editing = nil }
                if item.promptID != nil {
                    Button("删除", role: .destructive) {
                        state.deletePrompt(id: item.promptID!)
                        editing = nil
                    }
                }
                Button("保存") {
                    save(item)
                }
                .buttonStyle(.borderedProminent)
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