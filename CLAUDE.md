# Focus&Pause

## 项目来历

- 从 FocusGuard 的**完整 macOS 代码**改名而来（保留全部功能），不是新写的最小应用。
- 改名已完成：target / bundle = `FocusPause` / `com.focuspause.app`；后台 helper = `com.focuspause.helper`（独立 Mach 服务名与路径，**不会与已安装的 FocusGuard helper 冲突**）。
- 目录结构：`Sources/FocusPause`（主应用）、`Sources/FocusPauseHelper`（LaunchDaemon）、`Sources/FocusPauseHelperShared`（XPC 协议）。
- 当前发布版本：`BundleResources/Info.plist` 为 **2.0.4 / build 21**。

## 已具备功能（继承自 FocusGuard，勿动屏蔽逻辑）

- 网站屏蔽（/etc/hosts）、App 屏蔽（强制退出）、网络拦截（DNS 127.0.0.1）
- 专注计时、延时屏蔽、冷静期、屏蔽密码、紧急退出、定时/屏蔽后提醒
- 软件更新检查（`Services/Updater.swift`，现指向 gitee `xiaohe529/focus-pause`，仓库未建→静默失败，不影响使用）
- 后台 helper 守护进程（仅白名单命令：hosts 写入 + networksetup DNS）

## 构建 / 发布

```bash
swift build                  # 验证编译
./build-app.sh [release]     # 组装 universal .app（含 helper）
./make-release.sh <版本号>    # 生成 zip（如 ./make-release.sh 1.0.0）
create-dmg --volname "FocusPause" --background dmg-background.png \
  --window-size 660 400 --icon-size 128 \
  --icon "Focus&Pause.app" 165 200 --app-drop-link 495 200 \
  --no-internet-enable FocusPause-v1.0.0.dmg ".build/Focus&Pause.app"
# 重打包前：pkill -f "Focus&Pause.app/Contents/MacOS/FocusPause"
```

## 本期目标（在现有功能上加「正念 + 休息」）

1. **正念呼吸**：方箱呼吸 4-4-4-4（吸/屏/呼/屏各 4 秒），`TimelineView` 驱动圆的缩放动画（参考 `Views/FocusTimerView.swift` 的 TimelineView 倒计时模式），1/3/5 分钟可选，config → running → done 三态，相位文字「吸气/屏息/呼气/屏息」。
2. **五感着陆**：先一页清单（5 看 / 4 触 / 3 听 / 2 闻 / 1 尝），再「开始分步引导」进入分步模式，每步大字数字 + 引导语 + 下一步/完成 + 进度点。
3. **鼓励语卡片**：用户自设句子，卡片轮播（上一条 / 随机 / 下一条），可增删改；当前句在呼吸/着陆练习页作陪伴文字；UserDefaults 持久化（key 建议 `encouragementCards`，AppState 加 helpers）。
4. **休息提醒**：每隔 N 分钟弹窗提醒休息（默认 60，设置里可调、可开关），弹窗内可一键进入呼吸/练习。提醒循环参考 `AppState.startReminderLoop` 的 Task 循环 + NSAlert 模式。
5. **弹窗接入**：把练习入口接入现有 NSAlert 弹窗（如屏蔽后 / 专注计时结束 / 延时屏蔽到期提醒），新增「暂停一下」选项。

## 设计系统（中性灰墨 + 强调色 + 危险红）

- `Views/DesignSystem.swift` 是唯一入口：
  - `Color.focusAccent`：当前**强调色主题**（默认暖赭，见 `AccentTheme`）。用于正向主动作、
    一级导航当前分区、二级导航选中态 / 下划线、链接、运行中图标。
  - `Color.focusDanger`：砖红。**只用于破坏性 / 紧急动作**——解除屏蔽、拦截、紧急退出、
    结束正计时、删除密码、应急解锁。始终配白字。
  - `Color.focusInk`：墨色，用于中性的高强调元素、开关填充。
  - `surfaceCanvas` / `surfaceCard` / `surfaceWell` / `surfaceHairline` / `surfaceDivider` / `accentFg`。
  - `focusCard()` / `focusRow()` / `focusList()` / `focusChip()` / `MiniSegmented`。
- **三层导航刻意用三种不同样式，避免「两级一样」的重复感**：
  - 一级：标题栏里、**强调色实心胶囊**（最重要），居中，间距最疏。
  - 二级：**下划线文字**（无轨道、无填充），居中；与一级同一竖直中轴。
  - 卡片内模式切换：`MiniSegmented`（灰轨道 + 白胶囊，默认）或 `SubSegmentCard(.plain)`，居中。
    弹窗内的关键二选一（如「倒计时 / 正计时」）可传 `selectedStyle: .filled` 换成强调色实心，
    否则白胶囊在弹窗里几乎看不出选中。
- **标题栏**（`TitlebarTabs.swift` + `SettingsWindowController.installTitlebarTabs`）：
  只放两样——**应用名靠左**（红绿灯之后）+ **设置齿轮靠右**，与红绿灯同一水平线。
  一级导航在**窗口内容区**（`MainView.primaryTabs`，居中、间距 20）。
- **设置 → 外观**：主题（跟随系统 / 浅色 / 深色）+ 强调色（暖赭 / 陶土 / 青碧 / 苔绿 /
  靛蓝 / 紫棠 / 石墨，七选一），持久化在 `AppSettingsStore`
  （key `accentTheme` / `appearanceTheme`），改完立即生效。
- 开关统一用 `AlwaysActiveSwitchStyle`（30×17，开启＝强调色 / 关闭＝中性灰），别用原生 `.switch`。
- 圆角：控件 8 / 卡片 12 / 弹窗 14；窗口 720×620，最小 680×560。

## App 图标

- `make-icon.swift` 用 AppKit **按精确像素**绘制（不用 `NSImage.lockFocus`，否则 Retina 上会放大成 2 倍）。
  构图：一只探头偷看的可爱黑猫——近白圆底 + 墨色猫身 + 反白大眼睛 + 两只小爪 + 底部横条。
- 配色是**单色**（墨 + 灰白），刻意不用彩色：眼睛靠「反白 + 细墨环 + 高光」出神，耳朵内侧留白。
  和 App 的 `focusInk` / 灰底卡片语言一致，也符合 magpie「一块素底 + 一个形状」的观感。
- 改图标流程：
  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift make-icon.swift
  iconutil -c icns AppIcon.iconset -o BundleResources/AppIcon.icns
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./build-app.sh
  ```
- 每个尺寸都要实际看一眼（尤其 16×32）：猫耳和眼睛是识别锚点，太细会在小尺寸消失。

## DMG 安装引导页

- 背景是 `dmg-background.png`（1320×800 px @144 DPI，即 660×400 pt），由
  `make-dmg-background.swift` 生成（文字 + 弧形手绘箭头 + 留白）。
  **背景里不放 logo**——`Focus&Pause.app` 的图标由 Finder 自己画。
- 重新生成：
  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift make-dmg-background.swift
  ```
- 布局必须与 `create-dmg` 的坐标对齐（Finder 用左上角原点）：图标中心在 (165,200) / (495,200)，
  背景里的拖拽箭头画在这两块之间、与图标同一中线。

## 边界 / 注意

- 现有屏蔽、计时、密码逻辑已被用户验证，**不要改**。
- 弹窗文案简洁克制，中文。
- 发布前记得：重置版本号、确认更新源仓库。
