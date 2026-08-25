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
                .frame(width: 36, height: 20)
                .overlay(
                    Circle()
                        .fill(.white)
                        .shadow(radius: 1)
                        .padding(2)
                        .offset(x: configuration.isOn ? 8 : -8)
                )
                .onTapGesture { configuration.isOn.toggle() }
                .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
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
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1.0))
            .foregroundColor(.white)
            .clipShape(Capsule())
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
            .foregroundColor(color.opacity(configuration.isPressed ? 0.5 : 1.0))
    }
}
