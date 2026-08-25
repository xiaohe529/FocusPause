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

    private let cardTints: [Color] = [.focusAccent, .focusActive, .gray]

    private struct EditingItem: Identifiable {
        let id = UUID()
        let promptID: UUID?   // nil = 新增
        let kind: PromptItem.Kind
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("文字提示")
                VStack(alignment: .leading, spacing: 10) {
                    Text("给自己一些警醒与提示")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if state.textPrompts.isEmpty {
                        emptyText("还没有文字提示。")
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
                .focusCard()

                Divider().padding(.horizontal, -16)

                sectionHeader("一些提醒")
                VStack(alignment: .leading, spacing: 10) {
                    Text("展示在提醒弹窗里，作为文字提示。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if state.actionPrompts.isEmpty {
                        emptyText("还没有提醒。")
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
                .focusCard()
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
                .background(cardColor(for: item), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func cardColor(for item: PromptItem) -> Color {
        guard let index = state.textPrompts.firstIndex(where: { $0.id == item.id }) else {
            return Color.focusAccent.opacity(0.12)
        }
        let tint = cardTints[index % cardTints.count]
        return tint.opacity(0.14)
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
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
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
            .buttonStyle(AlwaysActiveButtonStyle(color: .focusAccent))
            .fixedSize()
            Spacer()
        }
    }

    @ViewBuilder
    private func emptyText(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.headline)
    }
}