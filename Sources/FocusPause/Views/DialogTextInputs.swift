import SwiftUI
import AppKit

// MARK: - Shared dialog field chrome

/// Matches the visual geometry of SwiftUI's `.roundedBorder` text fields while
/// allowing AppKit-backed fields below to own first responder/caret behavior.
private struct DialogFieldChrome: ViewModifier {
    var isFocused: Bool
    var height: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 7)
            .frame(height: height, alignment: .center)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? Color(nsColor: .controlAccentColor)
                            : Color.secondary.opacity(0.28),
                        lineWidth: 1
                    )
            }
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

private struct DialogTextEditorChrome: ViewModifier {
    var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(height: 64, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? Color(nsColor: .controlAccentColor)
                            : Color.secondary.opacity(0.28),
                        lineWidth: 1
                    )
            }
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

// MARK: - Text

struct DialogTextField: View {
    @Binding var text: String
    var placeholder: String = ""
    var alignment: NSTextAlignment = .left
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    var autoFocus = false
    var onSubmit: (() -> Void)? = nil
    var height: CGFloat = 24

    @State private var isFocused = false

    var body: some View {
        DialogTextFieldRepresentable(
            text: $text,
            placeholder: placeholder,
            alignment: alignment,
            font: font,
            autoFocus: autoFocus,
            onSubmit: onSubmit,
            onEditingChanged: { isFocused = $0 }
        )
        .modifier(DialogFieldChrome(isFocused: isFocused, height: height))
    }
}

private struct DialogTextFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var alignment: NSTextAlignment
    var font: NSFont
    var autoFocus: Bool
    var onSubmit: (() -> Void)?
    var onEditingChanged: ((Bool) -> Void)?

    func makeNSView(context: Context) -> CaretTextField {
        let field = CaretTextField()
        field.delegate = context.coordinator
        field.font = font
        field.placeholderString = placeholder
        field.alignment = alignment
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.stringValue = text
        if autoFocus {
            DispatchQueue.main.async { [weak field] in
                guard let field, let window = field.window else { return }
                window.makeFirstResponder(field)
            }
        }
        return field
    }

    func updateNSView(_ field: CaretTextField, context: Context) {
        field.placeholderString = placeholder
        field.alignment = alignment
        field.font = font
        if field.stringValue != text,
           field.currentEditor() == nil {
            field.stringValue = text
        }
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: DialogTextFieldRepresentable

        init(_ parent: DialogTextFieldRepresentable) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.onEditingChanged?(true)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onEditingChanged?(false)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit?()
            return true
        }
    }
}

// MARK: - Number

struct DialogNumberField: View {
    @Binding var number: Int
    var placeholder: String = ""
    var alignment: NSTextAlignment = .right
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    var onEditingChanged: ((Bool) -> Void)? = nil
    var allowedRange: ClosedRange<Int> = 1...480
    var height: CGFloat = 24

    @State private var isFieldFocused = false

    var body: some View {
        DialogNumberFieldRepresentable(
            number: $number,
            placeholder: placeholder,
            alignment: alignment,
            font: font,
            allowedRange: allowedRange,
            onEditingChanged: { focused in
                isFieldFocused = focused
                onEditingChanged?(focused)
            }
        )
        .modifier(DialogFieldChrome(isFocused: isFieldFocused, height: height))
    }
}

private struct DialogNumberFieldRepresentable: NSViewRepresentable {
    @Binding var number: Int
    var placeholder: String
    var alignment: NSTextAlignment
    var font: NSFont
    var allowedRange: ClosedRange<Int>
    var onEditingChanged: ((Bool) -> Void)?

    func makeNSView(context: Context) -> CaretTextField {
        let field = CaretTextField()
        field.delegate = context.coordinator
        field.font = font
        field.placeholderString = placeholder
        field.alignment = alignment
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.stringValue = String(number)
        return field
    }

    func updateNSView(_ field: CaretTextField, context: Context) {
        field.placeholderString = placeholder
        field.alignment = alignment
        field.font = font
        let externalText = String(number)
        if field.stringValue != externalText,
           field.currentEditor() == nil {
            field.stringValue = externalText
            context.coordinator.lastSyncedText = externalText
        }
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: DialogNumberFieldRepresentable
        var lastSyncedText: String

        init(_ parent: DialogNumberFieldRepresentable) {
            self.parent = parent
            lastSyncedText = String(parent.number)
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.onEditingChanged?(true)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let normalized = Self.clampedValue(
                field.stringValue,
                fallback: parent.number,
                range: parent.allowedRange
            )
            field.stringValue = String(normalized)
            parent.number = normalized
            lastSyncedText = field.stringValue
            parent.onEditingChanged?(false)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let parsed = Int(field.stringValue.filter(\.isNumber))
            guard let parsed else { return }
            let clamped = min(max(parsed, parent.allowedRange.lowerBound), parent.allowedRange.upperBound)
            parent.number = clamped
            lastSyncedText = field.stringValue
        }

        private static func clampedValue(_ raw: String, fallback: Int, range: ClosedRange<Int>) -> Int {
            guard let parsed = Int(raw.filter(\.isNumber)) else { return fallback }
            return min(max(parsed, range.lowerBound), range.upperBound)
        }
    }
}

// MARK: - Secure text

struct DialogSecureField: View {
    @Binding var text: String
    var placeholder: String = ""
    var autoFocus = false
    var onSubmit: (() -> Void)? = nil
    var height: CGFloat = 24

    @State private var isFocused = false

    var body: some View {
        DialogSecureFieldRepresentable(
            text: $text,
            placeholder: placeholder,
            autoFocus: autoFocus,
            onSubmit: onSubmit,
            onEditingChanged: { isFocused = $0 }
        )
        .modifier(DialogFieldChrome(isFocused: isFocused, height: height))
    }
}

private struct DialogSecureFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var autoFocus: Bool
    var onSubmit: (() -> Void)?
    var onEditingChanged: ((Bool) -> Void)?

    func makeNSView(context: Context) -> CaretSecureTextField {
        let field = CaretSecureTextField()
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.stringValue = text
        if autoFocus {
            DispatchQueue.main.async { [weak field] in
                guard let field, let window = field.window else { return }
                window.makeFirstResponder(field)
            }
        }
        return field
    }

    func updateNSView(_ field: CaretSecureTextField, context: Context) {
        field.placeholderString = placeholder
        if field.stringValue != text,
           field.currentEditor() == nil {
            field.stringValue = text
        }
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: DialogSecureFieldRepresentable

        init(_ parent: DialogSecureFieldRepresentable) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.onEditingChanged?(true)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onEditingChanged?(false)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit?()
            return true
        }
    }
}

// MARK: - Multiline text

struct DialogTextEditor: View {
    @Binding var text: String
    var placeholder: String = ""
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    var autoFocus = false

    @State private var isFocused = false

    var body: some View {
        DialogTextEditorRepresentable(
            text: $text,
            placeholder: placeholder,
            font: font,
            autoFocus: autoFocus,
            onEditingChanged: { isFocused = $0 }
        )
        .modifier(DialogTextEditorChrome(isFocused: isFocused))
    }
}

private struct DialogTextEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: NSFont
    var autoFocus: Bool
    var onEditingChanged: ((Bool) -> Void)?

    func makeNSView(context: Context) -> DialogTextView {
        let view = DialogTextView()
        view.textView.delegate = context.coordinator
        view.text = text
        view.placeholder = placeholder
        view.font = font
        if autoFocus {
            DispatchQueue.main.async { [weak view] in
                guard let view, let window = view.window else { return }
                window.makeFirstResponder(view)
            }
        }
        return view
    }

    func updateNSView(_ view: DialogTextView, context: Context) {
        view.placeholder = placeholder
        view.font = font
        if view.text != text {
            view.text = text
        }
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DialogTextEditorRepresentable

        init(_ parent: DialogTextEditorRepresentable) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onEditingChanged?(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onEditingChanged?(false)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

@MainActor
final class DialogTextView: NSView {
    private let scrollView = NSScrollView()
    let textView = PlaceholderTextView()

    var text: String {
        get { textView.string }
        set { textView.string = newValue }
    }

    var placeholder: String {
        get { textView.placeholder }
        set { textView.placeholder = newValue }
    }

    var font: NSFont {
        get { textView.font ?? .systemFont(ofSize: NSFont.systemFontSize) }
        set { textView.font = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.font = font
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0

        scrollView.documentView = textView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class PlaceholderTextView: NSTextView {
    var placeholder = ""

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty, placeholder.isEmpty == false,
              let container = textContainer, let layoutManager = layoutManager else { return }

        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: 0, length: 0),
            actualCharacterRange: nil
        )
        let lineRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphRange.location,
            effectiveRange: nil
        )
        let origin = textContainerOrigin
        let rect = NSRect(
            x: origin.x,
            y: origin.y + lineRect.minY,
            width: max(0, container.containerSize.width),
            height: lineRect.height
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        (placeholder as NSString).draw(in: rect, withAttributes: attributes)
    }
}

// MARK: - AppKit fields

/// AppKit field that deliberately takes first responder on the first mouse-down.
final class CaretTextField: NSTextField {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

final class CaretSecureTextField: NSSecureTextField {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}
