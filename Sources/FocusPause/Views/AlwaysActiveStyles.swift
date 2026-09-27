import SwiftUI

/// Custom ToggleStyle that renders a colored switch regardless of window key status.
struct AlwaysActiveSwitchStyle: ToggleStyle {
    let onColor: Color
    let offColor: Color

    init(onColor: Color = .focusAccent, offColor: Color = Color(white: 0.6)) {
        self.onColor = onColor
        self.offColor = offColor
    }

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Capsule()
                .fill(configuration.isOn ? onColor : offColor)
                .frame(width: 38, height: 22)
                .overlay(
                    Circle()
                        .fill(.white)
                        .shadow(radius: 1)
                        .padding(2.5)
                        .offset(x: configuration.isOn ? 8 : -8)
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
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .frame(minHeight: 30)
            .background(
                LinearGradient(
                    colors: [color.opacity(configuration.isPressed ? 0.78 : 1.0), color.opacity(configuration.isPressed ? 0.68 : 0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: Capsule()
            )
            .foregroundColor(.white)
            .clipShape(Capsule())
            .shadow(color: color.opacity(configuration.isPressed ? 0.18 : 0.24), radius: configuration.isPressed ? 3 : 6, y: 2)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Tinted button that avoids heavy solid fills in dialogs.
struct AlwaysActiveTintedButtonStyle: ButtonStyle {
    let color: Color

    init(color: Color = .secondary) {
        self.color = color
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 15)
            .padding(.vertical, 7)
            .frame(minHeight: 30)
            .background(
                color.opacity(configuration.isPressed ? 0.22 : 0.14),
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(color.opacity(0.28), lineWidth: 1)
            }
            .foregroundStyle(color)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Selectable chip used for preset durations in reminder dialogs.
struct AlwaysActiveSelectableButtonStyle: ButtonStyle {
    let isSelected: Bool
    var selectedColor: Color = .focusAccent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .frame(minHeight: 30)
            .background(
                isSelected
                    ? selectedColor.opacity(configuration.isPressed ? 0.78 : 1.0)
                    : Color.secondary.opacity(configuration.isPressed ? 0.20 : 0.12),
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(
                    isSelected ? Color.clear : Color.secondary.opacity(0.18),
                    lineWidth: 1
                )
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
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
