import SwiftUI

/// 极简冷静风设计系统：统一色板 + 统一卡片样式。
extension Color {
    /// 沉稳靛蓝：主强调色（开启屏蔽、选中态、主按钮）
    static let focusAccent = Color(red: 0.42, green: 0.47, blue: 0.72)
    /// 沉静青绿：屏蔽中/专注中状态
    static let focusActive = Color(red: 0.30, green: 0.60, blue: 0.55)
    /// 低饱和红：错误 / 紧急
    static let focusDanger = Color(red: 0.80, green: 0.35, blue: 0.32)
    /// 卡片底色（自适应明暗）
    static let focusCard = Color.secondary.opacity(0.12)
}

extension View {
    /// 统一卡片样式：圆角 10 + 内边距 + 自适应底色。
    func focusCard(cornerRadius: CGFloat = 10) -> some View {
        self
            .padding(12)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// 从左到右排列、放不下自动换行的流式布局：每个子视图按自身理想尺寸排布，间距紧凑。
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 二级子分段：紧凑横排卡片（图标 + 标题），尺寸比一级标签小、间距宽松、
/// 选中态用靛蓝浅底描边，与一级标签（实心胶囊）明显区分。
/// 可直接输入任意位数（含个位数）的数值小框：用字符串承载输入，解析后回写。
/// 避免 `TextField(value:format:)` 在 macOS 上不便输入个位数的问题。
struct MinuteField: View {
    let value: Int
    var width: CGFloat = 35
    let onChange: (Int) -> Void
    @State private var text: String

    init(value: Int, width: CGFloat = 35, onChange: @escaping (Int) -> Void) {
        self.value = value
        self.width = width
        self.onChange = onChange
        _text = State(initialValue: String(value))
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .frame(width: width)
            .onChange(of: text) { _, newText in
                let digits = newText.filter { $0.isNumber }
                guard let v = Int(digits), v > 0 else { return }
                onChange(v)
            }
            .onChange(of: value) { _, newValue in
                // 外部（步进器等）变化时同步显示
                if Int(text) != newValue { text = String(newValue) }
            }
    }
}

/// 行内操作按钮组（编辑 / 上移 / 删除）：默认透明隐藏、不可点，
/// `revealed` 为 true 时淡入显示。用于列表条目在鼠标悬停时才露出操作按钮。
struct RowActionButtons: View {
    var revealed: Bool
    var onEdit: (() -> Void)?
    var moveUp: (() -> Void)?
    var canMoveUp: Bool = true
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            if let moveUp {
                Button(action: moveUp) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(!canMoveUp)
            }
            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.focusDanger)
            }
        }
        .opacity(revealed ? 1 : 0)
        .animation(.easeInOut(duration: 0.12), value: revealed)
    }
}

struct SubSegmentCard<T: Hashable>: View {
    struct Option {
        let value: T
        let label: String
        let icon: String
    }

    let options: [Option]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 10) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.icon)
                            .font(.system(size: 14))
                        Text(option.label)
                            .font(.subheadline)
                    }
                    .foregroundStyle(selection == option.value ? Color.focusAccent : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        selection == option.value ? Color.focusAccent.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                selection == option.value ? Color.focusAccent.opacity(0.45) : Color.clear,
                                lineWidth: 1
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

