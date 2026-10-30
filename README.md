# LU

**基于 [Kazumi](https://github.com/Predidit/Kazumi) 二次修改的番剧客户端，个人自用，未商用。**

原项目 Kazumi 是 GPL-3.0 开源的番剧应用（作者 Predidit）。本仓库是它的个人修改版，
只为自己用着顺手改的：**不提供任何片源、不内置任何内容源、不对外分发、不收费。**

> 上游项目：<https://github.com/Predidit/Kazumi>
> 本仓库只保留二改部分，完整能力与文档请参考上游。

## 这是什么

- 包名沿用 `com.predidit.XL`，可以直接覆盖安装上游或旧版；
- 显示名改成 **LU**；
- 桌面端与手机端各有一套界面语言（拟态 / 粘土），见下。

## 相对上游的改动

**界面与交互**

- 桌面端拟态（Neumorphism）皮肤：侧栏、卡片、分段控件、进度轨按「浅色块 + 双向阴影 + 1px 硬描边」重做
- 手机端拟态底栏 + 拟态卡片，默认竖屏浅色
- 时间表：宽屏「一周七列」看板（内容区 ≥1180），窄屏仍是一天一页
- 推荐页：「继续观看」横滑卡片（取观看历史，点卡片直接续播）
- 加载骨架屏：推荐页、时间表、搜索页
- 对话框统一成自绘的粘土 / 拟态弹窗（`ClayDialog` / `NeuDialog`），不再用 Material `AlertDialog`
- 选集面板标「看过」、海报墙悬停浮起 + 快捷收藏、播放器快捷键速查表（`?`）
- Windows 无边框圆角窗口（透明背景 + 26px 圆角 + 八向缩放热区），可在设置里关掉

**播放与「一起看」**

- 弹幕热力条、卡顿自动换源、观看年报
- 一起看：快捷反应、3-2-1 倒计时、同步状态条、播放队列、温和追帧、投票、片源指纹、
  断线自动重连、房主接管、缺源兜底、置顶公告 / 敲一敲、快捷短语、网络诊断
- 独立 app 内音量、选集正倒序

**其他**

- Emby 媒体库（独立模块，历史单独分档）
- 托盘图标在退出前摘除（修上游遗留的通知区残影）
- 在线更新跟随本仓库的 Release；「关于 → 源代码」指向当前版本的发布页

## 构建

```bash
flutter pub get
flutter build apk --release          # Android
flutter build windows --release      # Windows
```

Windows 构建需要 Visual Studio 的 C++ 工具链。`media_kit` / `ech_http` 的 native hook
依赖 Windows SDK 路径，某些环境（`reg.exe` 被安全软件拦截导致读不到 SDK）需要手动补
`INCLUDE` / `LIB`。

## 免责声明

- 本项目**不提供、不内置、不分发任何影视内容或片源**，所有内容来自用户自行导入的第三方规则；
- 仅供个人学习与技术研究，**请勿用于商业用途**；
- 使用本项目产生的任何后果由使用者自行承担，与作者无关；
- 本项目遵循上游的 **GPL-3.0** 许可证，见 [LICENSE](LICENSE)。

## 致谢

上游 [Kazumi](https://github.com/Predidit/Kazumi) 及其所有贡献者，以及 media-kit、
Anime4K、Syncplay、xpath_selector、avbuild、hive_ce 等开源项目。
