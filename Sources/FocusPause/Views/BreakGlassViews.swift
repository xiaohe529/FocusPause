import SwiftUI

struct BreakGlassDialogView: View {
    let title: String
    var icon: String = "lock.open.rotation"
    var tint: Color = .focusAccent
    var message: String
    var requiresPassword: Bool = false
    var requiresConfirmationPhrase: Bool = false
    var submitTitle: String
    let onSubmit: (_ password: String, _ confirmationPhrase: String) -> String?

    @State private var password = ""
    @State private var confirmationPhrase = ""
    @State private var errorMessage = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DialogShell(width: 400) {
            DialogHeader(title: title, icon: icon, tint: tint)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if requiresConfirmationPhrase {
                VStack(alignment: .leading, spacing: 6) {
                    Text("确认语句")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DialogTextField(
                        text: $confirmationPhrase,
                        placeholder: AppState.breakGlassConfirmationPhrase,
                        height: 24
                    )
                    Text("请完整输入：\(AppState.breakGlassConfirmationPhrase)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if requiresPassword {
                VStack(alignment: .leading, spacing: 6) {
                    Text("屏蔽密码")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DialogSecureField(
                        text: $password,
                        placeholder: "输入密码",
                        autoFocus: true
                    )
                }
            }

            if !errorMessage.isEmpty {
                InfoBanner(style: .danger) {
                    Text(errorMessage)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } secondary: {
            Button("取消") { dismiss() }
                .buttonStyle(AlwaysActiveTintedButtonStyle())
        } primary: {
            Button(submitTitle) {
                if let failureMessage = onSubmit(password, confirmationPhrase) {
                    errorMessage = failureMessage
                } else {
                    dismiss()
                }
            }
            .buttonStyle(AlwaysActiveButtonStyle(color: tint))
        }
    }
}
