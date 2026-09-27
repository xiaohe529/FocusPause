import SwiftUI

struct BreakGlassDialogView: View {
    let title: String
    var icon: String = "lock.open.rotation"
    var tint: Color = .focusDanger
    var message: String
    var requiresPassword: Bool
    var submitTitle: String
    let onSubmit: (_ password: String) -> Bool

    @State private var password = ""
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

            if error {
                InfoBanner(style: .danger) {
                    Text("密码错误，请重新输入。")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                Button(submitTitle) {
                    if onSubmit(password) {
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: FocusRadius.modal))
    }
}
