# FocusPause

## 项目来历

- 从 FocusGuard 的**完整 macOS 代码**改名而来（保留全部功能），不是新写的最小应用。
- 改名已完成：target / bundle = `FocusPause` / `com.focuspause.app`；后台 helper = `com.focuspause.helper`（独立 Mach 服务名与路径，**不会与已安装的 FocusGuard helper 冲突**）。
- 目录结构：`Sources/FocusPause`（主应用）、`Sources/FocusPauseHelper`（LaunchDaemon）、`Sources/FocusPauseHelperShared`（XPC 协议）。
- 当前 `BundleResources/Info.plist` 版本仍是拷贝来的 **1.1.8 / build 10**，正式发布前需重置为 **1.0.0**。

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
  --icon "FocusPause.app" 165 200 --app-drop-link 495 200 \
  --no-internet-enable FocusPause-v1.0.0.dmg .build/FocusPause.app
# 重打包前：pkill -f "FocusPause.app/Contents/MacOS/FocusPause"
```

## 本期目标（在现有功能上加「正念 + 休息」）

1. **正念呼吸**：方箱呼吸 4-4-4-4（吸/屏/呼/屏各 4 秒），`TimelineView` 驱动圆的缩放动画（参考 `Views/FocusTimerView.swift` 的 TimelineView 倒计时模式），1/3/5 分钟可选，config → running → done 三态，相位文字「吸气/屏息/呼气/屏息」。
2. **五感着陆**：先一页清单（5 看 / 4 触 / 3 听 / 2 闻 / 1 尝），再「开始分步引导」进入分步模式，每步大字数字 + 引导语 + 下一步/完成 + 进度点。
3. **鼓励语卡片**：用户自设句子，卡片轮播（上一条 / 随机 / 下一条），可增删改；当前句在呼吸/着陆练习页作陪伴文字；UserDefaults 持久化（key 建议 `encouragementCards`，AppState 加 helpers）。
4. **休息提醒**：每隔 N 分钟弹窗提醒休息（默认 60，设置里可调、可开关），弹窗内可一键进入呼吸/练习。提醒循环参考 `AppState.startReminderLoop` 的 Task 循环 + NSAlert 模式。
5. **弹窗接入**：把练习入口接入现有 NSAlert 弹窗（如屏蔽后 / 专注计时结束 / 延时屏蔽到期提醒），新增「暂停一下」选项。

## 设计系统（沿用极简冷静风）

- `Views/DesignSystem.swift`：`focusCard()`（圆角 10 + 自适应底）、`Color.focusAccent`（靛蓝）/ `focusActive`（青绿）/ `focusDanger`（低饱和红）。
- 深浅色自适应（用 `Color.secondary` 语义色），新增 UI 一律走这套。

## 边界 / 注意

- 现有屏蔽、计时、密码逻辑已被用户验证，**不要改**。
- 弹窗文案简洁克制，中文。
- 发布前记得：重置版本号、确认更新源仓库。
