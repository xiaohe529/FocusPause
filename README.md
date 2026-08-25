# FocusPause — macOS 专注力守护工具

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-orange)]()

FocusPause 是一个 macOS 桌面应用，帮助你在需要专注时屏蔽网站、App 和网络，减少干扰。

> 适合：考研党、远程工作者、需要写代码/写论文但总想刷 B 站微博的人。

## 功能

| 模块 | 说明 |
|------|------|
| **网站屏蔽** | 通过 `/etc/hosts` 将网站域名指向 127.0.0.1，支持自定义规则 |
| **App 屏蔽** | 定时扫描运行中的应用，强制关闭被屏蔽的 App |
| **网络拦截** | 修改系统 DNS 为无效地址，全局断网（不影响局域网） |
| **专注计时** | 设置倒计时，计时结束前无法取消屏蔽（需密码） |
| **延时屏蔽** | 给自己一段自由浏览时间，倒计时结束后自动开启屏蔽 |
| **定时提醒** | 未屏蔽时每隔 N 分钟弹窗提醒"该开启了" |
| **密码保护** | 停止屏蔽需输入密码，增加操作摩擦防止一时冲动 |

## 安装

### macOS 14+（Apple Silicon 和 Intel 通用）

1. 从 [GitHub Releases](https://github.com/xiaohe529/FocusPause/releases) 或 [Gitee Releases](https://gitee.com/xiaohe529/focus-pause/releases) 下载 `FocusPause-v*.dmg`
2. **双击 DMG 文件**，会弹出一个窗口，左边是 FocusPause 图标，右边是 Applications 文件夹
3. **把 FocusPause 拖入 Applications 文件夹**（等于是复制到应用程序目录）
4. 拖完后可以**右键点击 DMG 图标 → 推出**，卸载 DMG
5. 打开 `/Applications` 文件夹，找到 FocusPause
6. **双击 FocusPause**，会弹出提示「无法验证开发者」
7. 点击「**取消**」
8. 打开「**系统设置 → 隐私与安全性**」
9. 在页面底部找到「FocusPause 已被阻止…」，点击「**仍要打开**」按钮
10. 弹出确认框，再次点击「**仍要打开**」，应用正常启动

> 这是 macOS Gatekeeper 对未签名 App 的正常拦截。**只需绕过一次**，之后就可以正常双击打开了。
>
> 部分旧版 macOS 上也可用右键（或按住 Control 点击）FocusPause → 选择「打开」的方式绕过。如果上述步骤不生效，再尝试终端运行 `xattr -cr /Applications/FocusPause.app`。

### 首次运行

首次点击「开启屏蔽」会弹出管理员密码框——这是安装后台助手的必要步骤，**只需授权一次**，之后所有屏蔽操作静默执行。

### 从源码构建

```bash
git clone https://github.com/xiaohe529/FocusPause.git
# 或国内镜像
git clone https://gitee.com/xiaohe529/focus-pause.git
cd FocusPause
./build-app.sh          # Debug 版
# 或
./build-app.sh release  # Release 版
open .build/FocusPause.app
```

要求：Xcode 16+ / Command Line Tools，macOS 14+，支持 Apple Silicon 和 Intel

## 架构

```
FocusPause.app
├── FocusPause          # 主应用（用户界面 + 业务逻辑）
├── FocusPauseHelper    # 后台助手（以 root 运行，仅做 /etc/hosts 写入和 DNS 设置）
│                       #   LaunchDaemon 安装到 /Library/LaunchDaemons/
├── FocusPauseHelperShared  # XPC 协议定义（app ↔ helper 通信接口）
```

安全要点：
- App 与 helper 通过 **NSXPCConnection** 通信，helper 以 root 权限运行
- 通信需验证共享 token，**恒定时间比较**防止时序攻击
- Helper 端**命令白名单**，只允许写入预定义路径的 hosts 文件和 networksetup DNS
- 屏蔽密码存储于 UserDefaults（目的不是加密安全，而是增加操作摩擦防止冲动解锁）

## 屏蔽原理

- **网站屏蔽**：在 `/etc/hosts` 中插入 `127.0.0.1 <域名>`，使浏览器无法解析目标网站
- **App 屏蔽**：每 5 秒轮询 `NSWorkspace.runningApplications`，对匹配到的 App 先 `terminate()`，2 秒后若仍运行则 `kill(SIGKILL)`
- **网络拦截**：`networksetup -setdnsservers Wi-Fi 127.0.0.1`，DNS 指向本机无效端口，阻止所有域名解析

> 网络拦截依赖系统 DNS 设置。若使用公司 Wi-Fi 的 DHCP 自动下发 DNS，路由器 DNS 可能覆盖系统设置导致拦截无效。建议在「系统设置 → 网络 → Wi-Fi → DNS」中手动指定 DNS。

## 项目结构

```
FocusPause/
├── Sources/
│   ├── FocusPause/          # 主应用
│   │   ├── Models/          # BlockRule, FocusTimerState
│   │   ├── Views/           # SwiftUI 视图
│   │   ├── Services/        # 各服务（Hosts/App/WiFi Blocker, Keychain, Helper Installer 等）
│   │   ├── AppState.swift   # 全局状态管理
│   │   └── FocusPauseApp.swift
│   ├── FocusPauseHelper/    # 后台 LaunchDaemon
│   └── FocusPauseHelperShared/  # 共享协议与常量
├── BundleResources/         # Info.plist 等
├── Package.swift            # SwiftPM 配置
├── build-app.sh             # 构建 → .app bundle
├── make-release.sh          # .app → zip 发布包
└── LICENSE
```

## License

MIT © 2025 FocusPause Contributors

---

## 致谢

如果你觉得有用，欢迎给个 ⭐ star。Bug 反馈和功能建议提 Issue 即可。
