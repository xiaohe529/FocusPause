import SwiftUI

struct WiFiView: View {
    @ObservedObject var state: AppState
    @State private var passwordInput = ""
    @State private var passwordError = false
    @State private var showPasswordPrompt = false
    @State private var showBlockConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: state.wifiDisabled ? "network.slash" : "network")
                    .font(.system(size: 40))
                    .foregroundStyle(state.wifiDisabled ? Color.focusActive : Color.focusAccent)

                Text(state.wifiDisabled ? "网络已拦截" : "网络正常")
                    .font(.title2.bold())

                Text(state.wifiDisabled
                     ? "DNS 已修改为无效地址，所有域名无法解析"
                     : "点击下方按钮将修改 DNS 为无效地址")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 6) {
                    HStack {
                        Text("当前状态")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(state.wifiDisabled ? "已拦截" : "正常")
                            .font(.subheadline.bold())
                            .foregroundStyle(state.wifiDisabled ? Color.focusActive : Color.focusAccent)
                    }
                    HStack {
                        Text("作用范围")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("系统级 DNS")
                            .font(.subheadline)
                    }
                    Text("通过将 DNS 服务器设为 127.0.0.1 阻止域名解析，从而切断网络访问。不影响局域网连接。恢复时需验证屏蔽密码。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 4)
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                        Text("专注计时期间：只可拦截网络，不可恢复网络，计时结束后自动解除限制。")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.focusDanger)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.focusDanger.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                    Text("注意：若网络通过 DHCP 自动下发 DNS（常见于公司 Wi-Fi），路由器下发的 DNS 会覆盖系统设置，此拦截可能无效。建议在「系统设置 → 网络 → Wi-Fi → 详细信息 → DNS」中手动指定 DNS 后再使用。")
                        .font(.caption)
                        .foregroundStyle(Color.focusDanger)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 2)
                }
                .focusCard()

                Button {
                    handleToggle()
                } label: {
                    Label(state.wifiDisabled ? "恢复网络" : "拦截网络",
                          systemImage: state.wifiDisabled ? "wifi" : "network.slash")
                        .padding(.vertical, 6)
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: state.wifiDisabled ? .focusActive : .focusDanger))
                .disabled(state.wifiBlocker.isProcessing)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showPasswordPrompt) {
            VStack(spacing: 16) {
                Text("输入密码以恢复网络")
                    .font(.headline)
                SecureField("输入密码", text: $passwordInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit { verifyAndEnableWiFi() }
                if passwordError {
                    Text("密码错误").foregroundStyle(.red).font(.caption)
                }
                HStack(spacing: 16) {
                    Button("取消") {
                        showPasswordPrompt = false
                        passwordInput = ""
                        passwordError = false
                    }
                    Button("确认") { verifyAndEnableWiFi() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 300, height: 180)
        }
        .alert("确认拦截网络？", isPresented: $showBlockConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认拦截") {
                Task { await state.wifiBlocker.toggle() }
            }
        } message: {
            Text("专注计时中，拦截后直到计时结束都无法恢复网络。确定要现在拦截吗？")
        }
        .onAppear { state.wifiBlocker.checkStatusQuiet() }
    }

    private func handleToggle() {
        // 专注计时中：可拦截网络，但禁止恢复
        if state.isLocked && state.wifiDisabled {
            state.lastError = "专注计时中，无法恢复网络。计时结束后才能恢复。"
            return
        }
        if state.wifiDisabled {
            passwordInput = ""
            passwordError = false
            showPasswordPrompt = true
        } else if state.isLocked {
            // 专注计时中拦截：提醒拦截后无法恢复
            showBlockConfirm = true
        } else {
            Task { await state.wifiBlocker.toggle() }
        }
    }

    private func verifyAndEnableWiFi() {
        if state.isLocked && state.wifiDisabled {
            showPasswordPrompt = false
            state.lastError = "专注计时中，无法恢复网络。计时结束后才能恢复。"
            return
        }
        if KeychainPassword.verify(passwordInput) {
            showPasswordPrompt = false
            passwordInput = ""
            passwordError = false
            Task { await state.wifiBlocker.toggle() }
        } else {
            passwordError = true
        }
    }
}
