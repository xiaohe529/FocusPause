import SwiftUI

struct BreakGlassDialogView: View {
    let title: String
    var icon: String = "lock.open.rotation"
    var tint: Color = .focusDanger
    var message: String
    var showConfirmationPhrase: Bool
    var submitTitle: String
    let onSubmit: (_ password: String, _ confirmationPhrase: String) -> Bool

    @State private var password = ""
    @State private var confirmationPhrase = ""
    @State private var error = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DialogHeader(
                title: title,
                icon: icon,
                tint: tint
            )

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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

            if showConfirmationPhrase {
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
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if error {
                InfoBanner(style: .danger) {
                    Text("验证未通过，请检查密码和确认语句。")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                Button(submitTitle) {
                    if onSubmit(password, confirmationPhrase) {
                        dismiss()
                    } else {
                        error = true
                    }
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: tint))
            }
            .padding(.top, 2)
        }
        .padding(22)
        .frame(width: 380, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
