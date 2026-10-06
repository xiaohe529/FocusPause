import SwiftUI

/// Custom ToggleStyle that renders a colored switch regardless of window key status.
struct AlwaysActiveSwitchStyle: ToggleStyle {
    let onColor: Color
    let offColor: Color

    init(onColor: Color = .focusAccent, offColor: Color = Color(light: Color(white: 0.78), dark: Color(white: 0.30))) {
        self.onColor = onColor
        self.offColor = offColor
    }

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Capsule()
                .fill(configuration.isOn ? onColor : offColor)
                .frame(width: 30, height: 17)     // 再收小一点，减少色块面积
                .overlay(
                    Circle()
                        .fill(Color.surfaceCard)
                        .padding(1.8)
                        .offset(x: configuration.isOn ? 6.5 : -6.5)
                )
                .onTapGesture { configuration.isOn.toggle() }
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: configuration.isOn)
        }
    }
}

/// Button style that keeps full color even when window is not key.
struct AlwaysActiveButtonStyle: ButtonStyle {
    let color: Color

    init(color: Color = .focusAccent) {
        self.color = color
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            // 收紧：magpie 的按钮是小圆角矩形，不是厚胶囊，色块面积更小。
            .padding(.horizontal, 13)
            .padding(.vertical, 5)
            .frame(minHeight: 28)
            .background(
                color.opacity(configuration.isPressed ? 0.82 : 1.0),
                in: RoundedRectangle(cornerRadius: FocusRadius.control, style: .continuous)
            )
            // 危险色（砖红）始终配白字；其余实心按钮用随明暗翻转的 accentFg。
            .foregroundStyle(color == Color.focusDanger ? Color.white : Color.accentFg)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 次级按钮（magpie 的 `.u__btn` 默认态）：中性底 + 1px 细线 + 主文字。
/// 刻意不用彩色底 / 彩色描边——浅色染出来的「淡紫描边药丸」正是要避免的廉价感。
/// 颜色只留给真正的主动作（`AlwaysActiveButtonStyle`）。
struct AlwaysActiveTintedButtonStyle: ButtonStyle {
    /// 保留参数以兼容调用点，但次级按钮一律中性呈现，不再染色。
    init(color: Color = .secondary) {}

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(minHeight: 30)
            .background(
                configuration.isPressed ? Color.surfaceWell : Color.surfaceCard,
                in: RoundedRectangle(cornerRadius: FocusRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: FocusRadius.control, style: .continuous)
                    .strokeBorder(Color.surfaceHairline, lineWidth: 1)
            }
            .foregroundStyle(Color.primary)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 可选择的预设（时长 / 模式）：选中 = 浅主色底 + 主色文字（去描边），
/// 未选 = 中性 pill 底。选中靠「底 + 文字色」表达，不用彩色描边。
struct AlwaysActiveSelectableButtonStyle: ButtonStyle {
    let isSelected: Bool
    var selectedColor: Color = .focusAccent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .frame(minHeight: 30)
            // 选中非常明确：强调色浅底 + 强调色描边 + 强调色文字，一眼能看出选了哪个。
            .background(
                isSelected ? selectedColor.opacity(configuration.isPressed ? 0.22 : 0.14) : Color.surfaceWell,
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(
                    isSelected ? selectedColor.opacity(0.55) : Color.surfaceHairline,
                    lineWidth: 1
                )
            }
            .foregroundStyle(isSelected ? selectedColor : Color.primary)
            .animation(.easeOut(duration: 0.14), value: isSelected)
    }
}

/// Borderless button that keeps its color when window is not key.
struct AlwaysActiveBorderlessStyle: ButtonStyle {
    let color: Color

    init(color: Color = .secondary) {
        self.color = color
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .frame(width: 30, height: 30)
            .background(
                Circle().fill(Color.secondary.opacity(configuration.isPressed ? 0.18 : 0.10))
            )
            .foregroundStyle(color.opacity(configuration.isPressed ? 0.5 : 1.0))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
