import SwiftUI
import AppKit

/// 自绘模态面板的公共装配：NSPanel 的无标题栏样式、能成为 key window、居中、精确按内容撑开。
/// `PracticePromptPanel` 与 `NoticeDialogView` 共用，避免两处配置漂移。
@MainActor
enum DialogPanelFactory {
    /// 弹窗出现前的状态，用于关闭后把现场恢复回去。
    private struct PriorState {
        let appWasActive: Bool
        /// 主窗口在弹窗出现前是否可见；为 nil 表示当时没有主窗口。
        let mainWindow: NSWindow?
    }
    /// 栈而非单个值：一个弹窗里可能再弹一个（如「停止屏蔽被锁」→ 提示后仍要输密码），
    /// 单个变量会被内层弹窗覆盖，外层关闭时就会把现场还原错。
    private static var priorStates: [PriorState] = []

    static func makePanel() -> FocusModalPanel {
        let panel = FocusModalPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.titled, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 让 utility 面板能正常成为 key window（默认 becomesKeyOnlyIfNeeded=true 会拒绝键盘焦点，
        // 导致弹窗里的输入框点进去不显示光标）。
        panel.becomesKeyOnlyIfNeeded = false
        panel.worksWhenModal = true
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.styleMask.insert(.fullSizeContentView)
        return panel
    }

    /// 按内容实际高度精确撑开并锁定尺寸，然后居中于主屏幕。
    static func present(_ panel: FocusModalPanel, contentSize: NSSize) {
        let size = NSSize(width: max(380, min(contentSize.width, 480)), height: max(150, contentSize.height))
        panel.setContentSize(size)
        panel.contentMinSize = size
        panel.contentMaxSize = size
        panel.setFrame(NSRect(origin: panel.frame.origin, size: size), display: false)

        // 手动居中：窗口尚未上屏时 center() 可能失效，导致面板落在屏幕上方。
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = panel.frame
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - frame.width / 2,
                y: screen.visibleFrame.midY - frame.height / 2
            ))
        }

        // 这些弹窗多在用户正用别的 App 时弹出，而激活本 App 会把主窗口一起顶到前面，
        // 看起来像「主界面自己冒出来了」。先记下现场：本来不是前台 / 主窗口本来是否可见，
        // 关掉弹窗后照原样还原。
        // 取「主窗口」= 可见的非面板窗口（悬浮目标窗是 NSPanel，排除掉）。
        let main = NSApp.windows.first { $0.isVisible && !($0 is NSPanel) }
        priorStates.append(PriorState(appWasActive: NSApp.isActive, mainWindow: main))
        if !NSApp.isActive {
            // 只把主窗口暂时收起来；弹窗自己会正常显示。
            main?.orderOut(nil)
        }

        // 激活 app：弹窗需要是激活态，SwiftUI 文本框才会真正绘制光标。
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
    }

    /// 弹窗关闭后还原现场：本 App 之前不在前台，就把主窗口的可见性恢复成原样并让出前台，
    /// 用户原来在用的 App 会回到最前，不会有「处理完弹窗主界面跳出来」的感觉。
    static func restoreAfterModal() {
        guard let prior = priorStates.popLast() else { return }
        if !prior.appWasActive {
            if let main = prior.mainWindow {
                main.orderFront(nil)
            }
            NSApp.deactivate()
        }
    }
}

/// 通用的小提示弹窗：和主界面用同一套设计语言（DialogShell 白卡 + 主题色按钮）。
/// 替代系统 `NSAlert`——后者的按钮在无 key window 时会是灰/黑色，和其余 UI 不一致。
struct NoticeDialogView: View {
    struct Action {
        let title: String
        /// 主按钮（实心主题色）。其余都是中性次级按钮。
        var isPrimary: Bool = false
        var tint: Color = .focusAccent
        let handler: () -> Void
    }

    var title: String
    var icon: String = "info.circle"
    var message: String
    var highlights: [String] = []
    /// 可选勾选项（如「下次不再提醒」）；勾选状态通过 `onCheckboxChange` 回传。
    var checkboxTitle: String? = nil
    var checkboxInitiallyOn: Bool = false
    var onCheckboxChange: ((Bool) -> Void)? = nil
    var actions: [Action]

    @State private var checkboxOn = false

    var body: some View {
        DialogShell(width: 400) {
            DialogHeader(title: title, icon: icon, tint: .focusAccent)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !highlights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(highlights, id: \.self) { item in
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                            Text(item)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(10)
                .background(Color.surfaceWell, in: RoundedRectangle(cornerRadius: FocusRadius.control, style: .continuous))
            }

            if let checkboxTitle {
                Toggle(isOn: $checkboxOn) {
                    Text(checkboxTitle)
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
                .onChange(of: checkboxOn) { _, newValue in
                    onCheckboxChange?(newValue)
                }
                .onAppear { checkboxOn = checkboxInitiallyOn }
            }
        } secondary: {
            ForEach(Array(actions.enumerated().filter { !$0.element.isPrimary }), id: \.offset) { _, action in
                Button(action.title, action: action.handler)
                    .buttonStyle(AlwaysActiveTintedButtonStyle())
            }
        } primary: {
            ForEach(Array(actions.enumerated().filter { $0.element.isPrimary }), id: \.offset) { _, action in
                Button(action.title, action: action.handler)
                    .buttonStyle(AlwaysActiveButtonStyle(color: action.tint))
            }
        }
    }
}

/// 把 `NoticeDialogView` 包进 NSPanel 以模态方式运行，返回用户点中的按钮下标。
/// 与 `PromptPanelPresenter` 同一套面板设置（能成为 key window、输入框第一次点击即有光标）。
@MainActor
enum NoticeDialogPresenter {
    /// 返回被点击按钮的索引；关闭（Esc / 直接关窗）返回 nil。
    @discardableResult
    static func run(_ dialog: NoticeDialogView) -> Int? {
        let panel = DialogPanelFactory.makePanel()

        let state = PanelChoiceState()
        let wrapped = dialog.actions.enumerated().map { index, action in
            NoticeDialogView.Action(title: action.title, isPrimary: action.isPrimary, tint: action.tint) {
                state.index = index
                panel.orderOut(nil)
                NSApp.stopModal()
            }
        }
        var view = dialog
        view.actions = wrapped

        let controller = FocusHostingController(rootView: view)
        panel.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
        DialogPanelFactory.present(panel, contentSize: controller.view.fittingSize)
        NSApp.runModal(for: panel)

        DialogPanelFactory.restoreAfterModal()
        return state.index
    }

    private final class PanelChoiceState {
        var index: Int?
    }
}
