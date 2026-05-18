# Emby iOS Player

[English](README.md)

一个非官方的 Emby 兼容 iOS/tvOS 客户端，重点是原生 SwiftUI 界面和基于 libmpv 的播放体验。

本项目是基于 Swiftfin UI 与导航代码进行的社区移植版本，服务端接口边界已适配 Emby API，iOS 播放路径接入本地 libmpv。项目不隶属于 Emby、Jellyfin 或 Swiftfin，也未获得它们的官方背书。

## 当前状态

本仓库仍在活跃开发中。当前 iOS App 已支持连接 Emby 服务器、登录、浏览媒体库、搜索、查看详情、继续观看、播放进度回传，以及通过本地 libmpv 路径播放媒体。

当前重点：

- Emby 认证、会话存储、公开用户、服务器信息和品牌配置。
- 首页、媒体库、收藏、搜索、详情页、季、集、继续观看流程。
- 基于 libmpv 的视频播放，包含自定义 iOS 控制层、字幕、音轨/字幕选择、断点续播、seek、倍速、亮度、音量和上下集导航。
- 播放进度回传到 Emby。
- iPhone 优先的 UI 行为，包括横屏播放。

## 目录结构

- `Emby/` - App 专属视图、入口、libmpv bridge 和播放器 UI。
- `Shared/` - 共享模型、导航协调器、ViewModel、Emby API 层和复用 UI。
- `Translations/` - 本地化字符串。
- `Documentation/` - 移植说明、播放器说明和贡献说明。
- `PreferencesView/` - App 使用的本地 Swift Package。
- `XcodeConfig/` - Xcode 配置文件。本地签名配置不应提交。

## 环境要求

- macOS 和较新的 Xcode。
- 与本地 Xcode 匹配的 iOS SDK。
- Homebrew，用于安装可选的格式化和 lint 工具。
- 真机安装需要有效的 Apple 开发者团队。
- 本地构建好的 iOS 版 libmpv 依赖包。

当前 Xcode 工程默认从以下路径查找 libmpv 产物：

```text
../../build/Libmpv.xcframework
```

该路径不会提交到仓库。你需要自己构建或放置 `Libmpv.xcframework`，或者按本地环境调整 Xcode 的 header/linker search paths。

## 快速开始

安装可选开发工具：

```bash
brew bundle
```

打开工程：

```bash
open Emby.xcodeproj
```

无签名构建模拟器版本：

```bash
xcodebuild build \
  -project Emby.xcodeproj \
  -scheme Emby \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

使用你自己的签名构建真机版本：

```bash
xcodebuild build \
  -project Emby.xcodeproj \
  -scheme Emby \
  -destination 'generic/platform=iOS' \
  DEVELOPMENT_TEAM=<YOUR_TEAM_ID> \
  CODE_SIGN_STYLE=Automatic
```

真机安装可以使用 Xcode，或者在签名构建完成后使用 `xcrun devicectl`。

## libmpv 说明

播放器代码围绕本地 libmpv bridge 设计。格式支持、硬解行为和性能表现取决于你构建的 libmpv、FFmpeg、MoltenVK 以及相关原生库。

本仓库不内置这些原生二进制产物。请不要把大型构建产物提交到 git；如果需要复现构建，请在文档中说明本地依赖和构建参数。

## 隐私与密钥

不要提交以下内容：

- 只属于你内网或个人环境的 Emby 服务器地址。
- 用户名、密码、API key、access token、session token。
- Apple 开发者团队配置。
- provisioning profile、签名证书、设备 ID、生成的 IPA。
- 本地媒体路径，或包含个人媒体库信息的截图。

本地签名覆盖配置应放在被忽略的本地配置文件中，例如：

```text
XcodeConfig/DevelopmentTeam.xcconfig
```

## 参与贡献

欢迎贡献。请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [Documentation/contributing.md](Documentation/contributing.md)。

提交 PR 前请确认：

- 保留 MPL-2.0 头部和上游归属信息。
- 新增服务端调用应通过 Emby 请求层。
- 播放相关改动尽量在真实 iPhone 上验证。
- 本地能完成受影响 target 的 Xcode 构建。
- 不提交生成产物或个人数据。

## 来源与归属

本项目包含从 Swiftfin 派生的代码。复制来的文件会在适用位置保留原始 MPL-2.0 文件头。更多上游归属见 [NOTICE.md](NOTICE.md)。

Emby、Jellyfin、Swiftfin、libmpv、FFmpeg、MoltenVK 等名称归各自所有者所有。

## 许可证

本仓库使用 Mozilla Public License 2.0。详见 [LICENSE.md](LICENSE.md)。
