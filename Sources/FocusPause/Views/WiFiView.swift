import SwiftUI

struct WiFiView: View {
    @ObservedObject var state: AppState
    @State private var passwordInput = ""
    @State private var passwordError = false
    @State private var showPasswordPrompt = false
    @State private var showBlockConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusHero

                InfoBanner(
                    style: state.isLocked && state.wifiDisabled ? .danger : .warning,
                    icon: state.isLocked && state.wifiDisabled ? "lock.fill" : "timer"
                ) {
                    Text(state.isLocked && state.wifiDisabled
                         ? "专注计时中：只能拦截网络，不能恢复网络；计时结束后可凭密码恢复。"
                         : "提示：拦截网络会把系统 DNS 指向无效地址；专注计时期间拦截后不能手动恢复，计时结束后可凭密码恢复。")
                        .fixedSize(horizontal: false, vertical: true)
                }

                detailsCard
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showPasswordPrompt) {
            PasswordDialogView(
                title: "恢复网络",
                icon: "wifi",
                tint: .focusActive,
                subtitle: "网络拦截当前已开启",
                message: "确认后 FocusPause 会立即恢复系统 DNS 设置。",
                confirmTitle: "恢复网络",
                confirmTint: .focusActive,
                errorMessage: passwordError ? "密码错误，请重试" : nil,
                password: $passwordInput,
                onSubmit: verifyAndEnableWiFi,
                onCancel: closePasswordPrompt
            )
        }
        .sheet(isPresented: $showBlockConfirm) {
            ConfirmDialogView(
                title: "确认拦截网络？",
                icon: "wifi.slash",
                tint: .focusDanger,
                message: "专注计时中拦截后，直到计时结束都无法恢复网络。",
                details: [
                    "DNS 会立即改为无效地址，网页和应用无法访问。",
                    "计时结束后不会自动恢复网络，可凭密码手动恢复。"
                ],
                confirmTitle: "确认拦截",
                cancelTitle: "暂不拦截"
            ) {
                showBlockConfirm = false
                Task { await state.wifiBlocker.toggle() }
            } onCancel: {
                showBlockConfirm = false
            }
        }
        .onAppear { state.wifiBlocker.checkStatusQuiet() }
    }

    private var statusHero: some View {
        HStack(spacing: 16) {
            Image(systemName: state.wifiDisabled ? "network.slash" : "network")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(state.wifiDisabled ? Color.focusActive : Color.focusAccent)
                .frame(width: 48, height: 48)
                .background(
                    (state.wifiDisabled ? Color.focusActive : Color.focusAccent).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 14)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(state.wifiDisabled ? "网络已拦截" : "网络正常")
                    .font(.headline)
                Text(state.wifiDisabled
                     ? "DNS 已指向本机无效地址"
                     : "通过系统 DNS 临时切断网络")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button {
                handleToggle()
            } label: {
                Label(
                    state.wifiDisabled ? "恢复" : "拦截",
                    systemImage: state.wifiDisabled ? "wifi" : "network.slash"
                )
                .frame(minWidth: 86, minHeight: 30)
            }
            .buttonStyle(AlwaysActiveButtonStyle(color: state.wifiDisabled ? .focusActive : .focusDanger))
            .disabled(state.wifiBlocker.isProcessing)
            .help(state.wifiDisabled ? "恢复网络" : "拦截网络")
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private var detailsCard: some View {
        SectionCard(title: "使用说明", icon: "info.circle", spacing: 10) {
            VStack(spacing: 8) {
                detailRow(
                    icon: "circle.grid.cross",
                    title: "作用范围",
                    value: "系统 DNS"
                )
                Divider()
                detailRow(
                    icon: "dot.radiowaves.left.and.right",
                    title: "局域网",
                    value: "不受影响"
                )
                Divider()
                detailRow(
                    icon: state.isLocked && state.wifiDisabled ? "timer" : "key.fill",
                    title: "恢复方式",
                    value: state.isLocked && state.wifiDisabled ? "计时结束可恢复" : "密码验证"
                )
            }

            if state.wifiDisabled {
                InfoBanner(style: .warning, icon: "network.slash", contentFont: .caption) {
                    Text("当前拦截的是 DNS：新打开的网页域名无法解析，但已打开的网页、已有连接、系统代理/VPN 和安全 DNS（DoH）仍可能联网。要彻底断应用，请配合 App 屏蔽。")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !state.wifiDisabled {
                InfoBanner(style: .warning, icon: "wifi.router", contentFont: .caption) {
                    Text("若网络通过 DHCP 自动下发 DNS（常见于公司 Wi-Fi），本地拦截可能被覆盖。建议在「系统设置 → 网络 → Wi-Fi → 详细信息 → DNS」中手动指定 DNS。")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func detailRow(
        icon: String,
        title: String,
        value: String,
        valueColor: Color = .primary
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Color.focusAccent)
                .frame(width: 18)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(valueColor)
        }
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

    private func closePasswordPrompt() {
        showPasswordPrompt = false
        passwordInput = ""
        passwordError = false
    }

    private func verifyAndEnableWiFi() {
        if state.isLocked && state.wifiDisabled {
            closePasswordPrompt()
            state.lastError = "专注计时中，无法恢复网络。计时结束后才能恢复。"
            return
        }
        if KeychainPassword.verify(passwordInput) {
            closePasswordPrompt()
            Task { await state.wifiBlocker.toggle() }
        } else {
            passwordError = true
        }
    }
}
