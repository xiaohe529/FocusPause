# Focus&Pause（专注暂停）

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-orange)]()

Focus&Pause 是一款 macOS 专注力守护工具：在你需要专注时屏蔽网站、App 和网络，并提供休息、正念呼吸、五感着陆等“暂停一下”练习，减少冲动解锁和无效刷屏。

> 适合考研党、远程工作者、写论文 / 写代码时容易被 B 站、微博、短视频打断的人。

## 功能

| 模块 | 说明 |
|------|------|
| 网站屏蔽 | 通过 `/etc/hosts` 把网站指向 `127.0.0.1`，支持自定义规则 |
| App 屏蔽 | 定时扫描并关闭被屏蔽的 App |
| 网络拦截 | 将系统 DNS 指向 `127.0.0.1`，快速阻断上网干扰 |
| 专注计时 | 支持倒计时与正计时，计时期间锁定屏蔽配置 |
| 延时屏蔽 | 给自己一段自由浏览时间，倒计时结束后自动开启屏蔽 |
| 定时屏蔽 | 按每天重复或一次性时间段自动开启屏蔽 |
| 休息计时 | 专注之间安排休息，结束后提醒回到专注 |
| 正念暂停 | 方箱呼吸、五感着陆、鼓励语卡片和暂停工具箱 |
| 密码保护 | 停止屏蔽需要输入密码，增加操作摩擦 |
| 应急解锁 | 紧急退出额度用完后，可通过密码、确认语句和冷静期解锁 |

## 下载安装

从 [GitHub Releases](https://github.com/xiaohe529/FocusPause/releases) 或 [Gitee Releases](https://gitee.com/xiaohe529/FocusPause/releases) 下载最新的 `FocusPause-v*.dmg`。

1. 双击 DMG 文件。
2. 在安装窗口中，把左侧的 **Focus&Pause** 拖到右侧的 **Applications** 文件夹。
3. 拖完后推出 DMG，打开 `/Applications/Focus&Pause.app`。
4. 首次开启屏蔽时，按提示授权安装后台助手；之后屏蔽操作会静默执行。

由于 App 当前未签名，macOS 可能提示“无法验证开发者”。请先点击 **取消**，然后打开
**系统设置 → 隐私与安全性**，在底部点击 **仍要打开**。

> 如仍被拦截，可在终端执行 `xattr -cr /Applications/Focus&Pause.app` 后重新打开。

## 从源码构建

```bash
git clone https://github.com/xiaohe529/FocusPause.git
# 或国内镜像：
git clone https://gitee.com/xiaohe529/FocusPause.git
cd FocusPause
./build-app.sh release
open ".build/Focus&Pause.app"
```

要求：macOS 14+，Xcode 16+ 或完整 Xcode 工具链；支持 Apple Silicon 和 Intel。

## 测试

```bash
swift test
./Scripts/test-coverage.sh
```

如果默认 Command Line Tools 缺少 Testing/XCTest 运行库，请使用完整 Xcode 工具链：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## 架构

```text
Focus&Pause.app
├── FocusPause              # 主应用：SwiftUI、状态管理、屏蔽调度
├── FocusPauseHelper        # 后台 helper：hosts 写入与 DNS 设置
└── FocusPauseHelperShared  # XPC 协议、域名归一化与共享校验
```

helper 通过 LaunchDaemon 安装到系统目录，主 App 与 helper 使用 XPC 通信，并校验共享 token。

## 发布

```bash
./build-app.sh release
./make-release.sh 2.0.2
```

如需构建 DMG，可在 `.build/Focus&Pause.app` 就绪后执行：

```bash
create-dmg --volname "FocusPause" --background dmg-background.png \
  --window-size 660 400 --icon-size 128 \
  --icon "Focus&Pause.app" 165 200 --app-drop-link 495 200 \
  --no-internet-enable FocusPause-v2.0.3.dmg ".build/Focus&Pause.app"
```

## 安全与隐私

- 屏蔽密码当前存储于 UserDefaults，用于增加冲动解锁的摩擦；旧 Keychain 数据会迁移。
- helper 只执行预定义的 hosts 写入和 DNS 设置命令。
- 屏蔽状态会在 App 退出后保留，避免通过重启 App 绕过专注计划。
- 删除 App 后，helper 的孤儿清理流程会恢复 hosts 和 DNS 设置。

## License

MIT © 2025 Focus&Pause Contributors

---

如果对你有帮助，欢迎给个 ⭐。Bug 反馈和功能建议请提 Issue。
