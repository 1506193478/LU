# LU 原生 iOS 端（SwiftUI）

Flutter 版 LU 的 iOS 原生重写。**纯 Swift + SwiftUI + UIKit 混合**，不依赖 Flutter 引擎，不引用任何 Dart 代码。

- 最低系统：iOS 16.0
- 播放内核：AVPlayer / AVKit
- 状态管理：`ObservableObject` + `@Published`（iOS 16 无 `@Observable`）
- 存储：UserDefaults（设置）+ 原子写入 JSON（收藏/历史/插件/下载）
- 依赖：零第三方 Pod / SPM（全部系统框架：AVFoundation、Network、Compression、CryptoKit、libxml2）

当前版本 **5.4.0 (5)**。

---

## 一、怎么跑起来

工程文件用 XcodeGen 描述，仓库里不存 `project.pbxproj`（避免手写 pbxproj 冲突）。

```bash
# macOS
brew install xcodegen
cd ios_native
xcodegen generate
open LU.xcodeproj
```

Xcode 里选 `LU` target → Signing & Capabilities → 选自己的 Team → 真机运行。

首次启动会走引导页；之后在「我的 → 设置」里可以配 Bangumi token（可选）、弹幕源（默认 B 站免凭据）、WebDAV。

---

### 用 CI 构建（推荐先跑一次）

`.github/workflows/ios-native.yml`：推 `ios_native/**` 或手动触发，会
`brew install xcodegen` → `xcodegen generate` → `xcodebuild`（无签名）→
产出 **`LU-native-unsigned.ipa`** 作为 artifact。它同时也是一次编译校验，
失败时会附带 `build.log`。

---

## 二、iOS 16 上的「液态玻璃」怎么做的

iOS 26 才有 `glassEffect`，iOS 17 才有 `layerEffect`。所以做了两套，运行时按能力选：

### A · Metal 逐像素折射（主路径）

`DesignSystem/LuMetalGlass.swift` + `LuGlassRefraction.metal`

iOS 16 没有 `layerEffect`，抓不到 SwiftUI 的「下层内容」——那就自己抓：

1. `UIGraphicsImageRenderer` 把**玻璃背后的窗口区域**渲成位图（截图前把自己隐藏，避免自采样）
2. 上传成 `MTLTexture`（1x 缩放，玻璃本来就要模糊，省一半带宽）
3. 自写 fragment shader 画回来：
   - 圆角矩形 **SDF** 切形状（1px 抗锯齿，外部丢弃）
   - 用 **SDF 法线**做边缘位移 → 这才是折射，不是模糊
   - RGB 三通道不同位移倍率采样 → **色散**
   - 位移后 5 tap 十字模糊 → **磨砂**（`frost`）
   - 法线·光照 + 边缘提亮 → **镜面高光 / 玻璃壁**
4. 落成 `LuLiquidGlass { }` / `.luLiquidGlass()`，参数与上面两个 React 库一一对应

参数：`refraction`（位移像素）、`frost`、`aberration`、`saturation`、`tint`。
抓图做了 0.5s 节流 + 系统切到后台时跳过；管线编译失败自动降级。

### B · 材质兜底

Metal 不可用、或显式传 `refraction: 0` 时走这层：

| 层 | 实现 | 作用 |
|---|---|---|
| 模糊底衬 | `.ultraThinMaterial` / `.thinMaterial` / `.regularMaterial` | 透光感，`LuGlassLevel` 三档 |
| 液面高光 | 顶部 45° 白色渐变 + `.plusLighter` | 表面反射 |
| 边缘浸润 | 内侧 12pt 渐变环 + `blur(7)` 裁进形状 | 玻璃壁厚度 |
| 色散 | 冷暖两条 0.8pt 描边 ±1pt 错位 | 色边 |

代码：`DesignSystem/LuGlass.swift`（基础材质）+ `LuLiquidGlass.swift`（统一入口）+ `LuMetalGlass.swift`（Metal 路径）。

### 关于 `liquid-glass-react` 和 `plasma-ui`

两个都是 **React / 浏览器** 库（npm 包 + SVG `feDisplacementMap` / WebGL canvas），
二进制层面链不进 SwiftUI 工程，`plasma-ui` 作者自己还写明「GPU 重、移动端跑不动」。
做法是**照配方用原生重搭**：

| Web 侧 | 原生实现 |
|---|---|
| `backdrop-filter: blur()` / `blurAmount` | Metal 路径走 shader 内 5 tap；兜底走 `UIVisualEffectView` |
| `feDisplacementMap` 边缘弯折 | shader 里用 SDF 法线做真实位移采样 |
| `saturation` | shader 内 luma 混合 / 兜底 `.saturation()` |
| `aberrationIntensity` | RGB 分通道位移倍率 / 兜底双色描边 |
| specular highlight | 法线·光照 / 兜底渐变叠 `plusLighter` |
| `elasticity` | `LuLiquidPressStyle`：按下 0.965 缩放 + 提亮 + 弹簧 |

### 动效

`DesignSystem/LuMotion.swift`：ShipSwift 的 `SWTransition`（16 种转场）与
`SWChangeEffect` 基于 iOS 17 的 `Transition` 协议，这里用 `AnyTransition` +
`Animatable` 修饰器重写等价版本：`.luBlur` / `.luBoing` / `.luWipe` / `.luIris(origin:)`，
外加 `.luShake(trigger:)` 与 `.luShimmer()`。播放器控制层、提示气泡、房间卡都在用。

**性能规则（继承 Flutter 侧教训）**：

- 列表卡片一律 `.thin`，只有底栏、浮层、播放器控件用 `.regular` / `.thick`
- 背景层 `LuBackdrop` 全部静态（渐变 + 5 颗光球 + 噪点 `Canvas`），**永不动画**
- 噪点用固定种子的 `Canvas` 一次性绘制，不做逐帧重建
- Metal 玻璃每张卡都要抓一次窗口，**只在首屏/静态卡片上用**；滚动列表、播放器控件（其下是 `AVPlayerLayer`，抓不到）一律 `refraction: 0`

---


---

## 三、功能清单

### 3.1 基础闭环

| 模块 | 文件 | 说明 |
|---|---|---|
| 应用壳 / 底栏 | `App/RootView.swift` | 5 项底栏（推荐/追番/一起看/Emby/我的），玻璃材质，**HG 短剧已整块移除** |
| 设计系统 | `DesignSystem/*` | 主题令牌（HIG 度量）、玻璃、背景、通用组件 |
| 推荐 | `Features/Popular` | Bangumi 每日放送、今日更新、高分推荐 |
| 追番 | `Features/Collect` | 本地收藏网格、长按取消 |
| 时间表 | `Features/Timeline` | 周一~周日分组 |
| 搜索 | `Features/Search` | Bangumi v0 搜索、搜索历史 |
| 详情 | `Features/Detail` | 模糊封面头、评分、BBCode 简介、剧集横滑、角色、**换源** |
| 播放器 | `Features/Player` | AVPlayer 自绘层、进度/倍速/±10s、亮度手势、长按 2x、切集、后台音频、AirPlay、**画中画**、**跳过片头**、**自动连播** |
| 我的 / 历史 / 设置 / 关于 | `Features/My`、`Features/Settings` | 观看历史、主题、播放、弹幕、WebDAV、日志、更新 |

### 3.2 本轮新增

| 能力 | 关键实现 | 说明 |
|---|---|---|
| **B 站弹幕源** | `Core/Networking/BilibiliDanmaku.swift` | wbi 签名搜索 + Bangumi `sites` 直取 season_id → `pgc/view/web/season` 取 cid → 弹幕 XML；标题匹配用 `LuTitleMatch`（归一化 + 相似度 + 配音/剧场版降权） |
| 弹幕调度 | `Features/Danmaku/Danmaku.swift` | `DanmakuService` 按设置选 B 站/弹弹play/关闭，统一做屏蔽词与简繁转换 |
| 简繁转换 | `Core/Support/LuOpenCC.swift` | 直接复用 `assets/opencc` 四份词典（词组最长匹配 + 单字兜底），按需加载 |
| BBCode 渲染 | `Core/Support/BBCode.swift` | 替换 Flutter 的 antlr4 BBCode 解析器（手写扫描，同一套标签），Bangumi 简介直接富文本 |
| 外挂字幕 | `Features/Player/Subtitle.swift` | SRT / WebVTT / ASS(SSA)，UTF-8 / GB18030 / Big5 自动识别，时间轴偏移，同名字幕自动挂载 |
| 离线下载 | `Core/Storage/DownloadManager.swift` | 直链走 `URLSessionDownloadTask`（可暂停续传）；HLS 自己拉分片并改写 `EXT-X-KEY` / `EXT-X-MAP`，完成后本地 m3u8 可离线播放 |
| 播放器截图 | `PlayerViewModel.snapshot()` | `AVPlayerItemVideoOutput` 取帧 → `CIImage` → 相册 |
| DLNA 投屏 | `Core/Networking/DLNA.swift` | BSD socket 发 SSDP M-SEARCH，解析描述 XML，SOAP 调 AVTransport（SetAVTransportURI / Play / Pause / Stop / Seek） |
| WebDAV | `Core/Networking/WebDAV.swift` | PROPFIND 列目录、Basic 认证、直接播放、同名侧挂字幕、加入下载 |
| 一起看 · 局域网 | `Core/Networking/SyncPlay.swift` | `NWListener` + `NWProtocolWebSocket` 起本地房间，Bonjour 广播 `_lu-sync._tcp`，页面直接显示 `IP:9301` 可复制 |
| 一起看 · 跨网络 | `Core/Networking/SyncPlayRelay.swift` + `server/lu-sync-relay.ts` | 公网 WebSocket 中继 + 5 位房间码，任何网络都能加入；断线自动重连（最多 5 次），房主权威、观众操作先到房主再广播 |
| 房间聊天 | `SyncPlaySession.sendChat` | 房主/观众双向，中继与局域网同一套 `chat` 消息 |
| 插件可视化编辑器 | `Features/Plugin/PluginEditorView.swift` | 全部规则可视化改写（含 XPath / API 双模式切换）+ 真实搜索验证 + 从文件/剪贴板导入 |
| 插件 API 规则 | `Features/Plugin/ApiRuleEngine.swift` | 对齐 Kazumi 的 `searchMode: api`：受限 JSONPath（`$.a.b` / `[*]` / `[0]` / `['k']`）、`@keyword` `@source` 模板变量、GET/POST + json/form 请求体、nested / delimited 两种章节格式 |
| 液态玻璃 | `DesignSystem/LuMetalGlass.swift` + `LuGlassRefraction.metal` | **Metal 逐像素折射**：截图底层 → `MTLTexture` → SDF 位移 + 色散 + 磨砂 + 高光；Metal 不可用自动退回材质版 |
| 动效 | `DesignSystem/LuMotion.swift` | 移植 ShipSwift 转场到 iOS 16 的 `AnyTransition`：`.luBlur` / `.luBoing` / `.luWipe` / `.luIris`，另含 `.luShake` / `.luShimmer` |
| 多源探测 | `DetailView.probeSources` | 一次并发搜所有启用的源，行内显示「命中 N 条 · 首条标题」，直接判断该换哪个源 |
| 播放设置 | `Features/Player/PlayerOptionsSheet.swift` | 内嵌**音轨**与**内嵌字幕**选择（AVMediaSelectionGroup）、画面比例（适应/填充/拉伸）、**画质增强**（锐化/鲜艳/降噪，`AVVideoComposition` + Core Image） |
| 短评 / 制作人员 | `BangumiAPI.comments/staffs` + `DetailView` | 吐槽箱（头像、评分、正文、日期）与制作人员横滑；之前只有模型没有接口 |
| 深链 | `Core/Support/LuDeepLink.swift` | `kazumi://subject/123`、`https://bgm.tv/subject/123` → 直接打开详情；冷启动与热启动都接 |
| 备份与恢复 | `Core/Support/LuBackup.swift` + `Features/Tools/BackupView.swift` | 收藏 / 历史 / 插件 / 常用设置打包成 JSON，分享导出、文件选择器合并恢复；敏感项不导出 |
| 直链解析 | `Core/Networking/LuURLResolver.swift` + `Features/Tools/URLResolveView.swift` | 粘贴分享文案 → 提取链接 → 抓页面找 m3u8/mp4（含 iframe 一层）→ 直接播 / 复制 / 加下载 |
| 追番提醒 | `Core/Support/LuUpdateReminder.swift` | 按 `airWeekday` 建 7 条每周本地通知，当天 20:00 提醒；收藏变化自动重排 |
| 主题色 | `LuAccent` + `LuTheme.accent` | 7 套强调色（深浅各一版），设置里实时切换 |
| 底栏自定义 | `AppSettings.hiddenTabs` | 可隐藏「推荐/追番/一起看/Emby/我的」任意项 |
| 一起看表情 | `SyncPlayView` | 12 个表情 + 6 个常用弹幕短语，点一下直接发 |
| 日志 | `Core/Support/LuLog.swift`、`Features/Logs` | 环形缓冲 3000 条 + 文件落盘，按级别过滤、搜索、导出 |
| 网络诊断 | `Core/Support/Diagnostics.swift` | Bangumi / B 站 / GitHub / 插件站点 / WebDAV 一次探测 |
| 引导页 | `Features/Onboarding` | 三步引导，`@AppStorage("lu.onboarded")` 只显示一次 |
| 应用内更新 | `Core/Support/UpdateChecker.swift` | GitHub Releases（原生线 `ios-v*`），版本比较、发布页、ipa 链接导出 |
| Emby 刮削 | `Features/Emby/EmbyMetadataSheet.swift` | 路线 A：服务端 `RemoteSearch` → `Apply`，客户端不存 TMDB Key；另有「标记已看」 |

### 3.3 明确的能力边界（不要误解）

| 项 | 现状 | 原因 |
|---|---|---|
| 种子 / 磁力 | **已按要求移除** | iOS 没有可用的 BT 协议栈，只能做元数据 + web seed 直连，收益太低，整块删掉 |
| 一起看 | 跨网络需要自备中继 | App 侧已实现，`server/lu-sync-relay.ts` 用 Deno 一行跑起来（或部署 Deno Deploy）即可；没有中继时局域网仍可用 |
| 应用内更新 | 只做检查与跳转 | iOS 不允许静默安装 ipa，正式分发要走 TestFlight / App Store |
| 深链 | 只认条目 | `kazumi://subject/123` 与 bgm.tv 条目页；搜索类链接不处理 |
| 插件规则 | XPath + API(JSONPath) | 覆盖 Kazumi 两种规则模式；WebView 反爬（验证码）与 JS 脚本源按决定不做——只影响极少数站点，普通 HTTP 源不受影响 |
| 液态玻璃 | Metal 抓帧折射 | iOS 16 的 `layer.render(in:)` 抓不到 `AVPlayerLayer` / `CAMetalLayer`，所以播放器控件上方只能用材质版；其余静态界面走真折射 |
| DLNA | 发送端 | 未做接收端（把手机当电视） |
| 弹幕 | 滚动/顶部/底部 | B 站高级弹幕（mode 7/8/9）按滚动处理 |

---

## 四、和 Flutter 版的对应关系

| Flutter | 原生 |
|---|---|
| `lib/pages/popular` `collect` `timeline` `search` `info` `player` `my` `settings` `about` `history` | `Features/*` 同名目录，已等价 |
| `lib/request/apis/bilibili_danmaku_api.dart` + `utils/bilibili_wbi.dart` + `utils/title_match.dart` | `BilibiliDanmaku.swift`（同一套 wbi 表、同一套匹配降权规则） |
| `lib/modules/danmaku/danmaku_ch_convert.dart` + `assets/opencc` | `LuOpenCC.swift` + `Resources/opencc/*.json` |
| `lib/services/download/*` | `DownloadManager.swift`（HLS 分片本地化，替代后台下载插件） |
| `lib/services/player/remote.dart`（DLNA） | `DLNA.swift`（SSDP + SOAP） |
| `lib/services/sync/webdav.dart` | `WebDAV.swift` |
| SyncPlay 外部服务 | `SyncPlay.swift`（自己起服务端） |
| `lib/bbcode`（antlr4） | `BBCode.swift`（手写扫描，无 antlr 运行时） |
| `lib/services/logging/logger.dart` | `LuLog.swift` |
| `lib/services/update/*` | `UpdateChecker.swift` |

**HG 短剧**：`lib/modules/hg/` 全部功能、连点解锁、Hive `hg` box 均不移植，原生端没有任何入口。

---

## 五、移植时踩到的关键点

1. **AVURLAsset 带请求头**：`AVURLAssetHTTPHeaderFieldsKey`，用于插件源 Referer 与 WebDAV Basic 认证。
2. **弹幕叠加**：不能用 `AVPlayerViewController`（自带控件层），必须自绘 `AVPlayerLayer` + SwiftUI overlay。
3. **HTML 解析**：`XMLDocument(data:options:.documentTidyHTML)` 走 libxml2 修复器，脏 HTML 也能建树。
4. **iOS 16 没有 `@Observable`**：全部 `ObservableObject`；`@StateObject` 初始化的类不要标 `@MainActor`。
5. **`ForEach` 不要用元组 key path**：`Array(x.enumerated())` + `id: \.element.id` 在部分 Swift 版本不可靠，统一改成 `ForEach(x.indices, id: \.self)`。
6. **弹幕解压**：B 站 `list.so` 返回裸 deflate，先判断首字节是否为 `<`，再走 `compression_decode_buffer(..., COMPRESSION_ZLIB)`。
7. **SSDP 组播**：`NWConnection` 不暴露 fd，无法 `IP_ADD_MEMBERSHIP`；M-SEARCH 用 BSD socket（只需要发组播、收回单播，不必 join）。
8. **WebSocket 服务端**：`NWParameters.tcp` 里把 `NWProtocolWebSocket.Options` 插到 `defaultProtocolStack.applicationProtocols` 第 0 位，握手指令与分帧都由系统处理。
9. **HLS 离线**：`EXT-X-KEY` 的 URI 改成本地 `key_0.bin`、`EXT-X-MAP` 改成本地 `init_0.mp4`，播放列表里所有分片改成相对文件名，AVPlayer 才能离线读。
10. **OpenCC 词典**：`LuNative/Resources/opencc/*.json` 会被 XcodeGen 当成 resource 拷进 bundle 根目录，用 `Bundle.main.url(forResource:)` 读取。

---

## 六、下一步建议

1. 真机首编译排错（Windows 上只能写代码，无法编译验证）。
2. 补插件 WebView 反爬（`WKWebView` + cookie 复用）与脚本源。
3. 收藏/历史的 WebDAV 同步（Flutter 有 `collect_sync_dialog`，原生端尚未做）。
4. 播放器音量手势、PiP、双字幕。
5. 图标与字体打包（`assets/fonts` → `Resources` + `UIAppFonts`）。
