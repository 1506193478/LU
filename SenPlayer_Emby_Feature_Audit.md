# SenPlayer → LU Emby 模块 功能对齐审计

> 目标：保持 Flutter、只改 Emby 模块，全量还原 SenPlayer 6.1.8（Android 1.0.0-b13 功能高度一致）的 UI / 功能 / 内核等价实现，排除全部会员购买与内购。
> 基线报告：`C:/Users/15061/WorkBuddy AI/2026-10-28-22-27-46/senplayer-analysis/SenPlayer_6.1.8_UI与功能全解.md`
> 图例：✅ 已实现 ｜ 🟡 部分实现 ｜ ❌ 缺失 ｜ ⛔ 会员相关（不做）
>
> **重要前提**：SenPlayer 是 SwiftUI（iOS）+ Compose（Android）原生应用，源码无法移植到 Flutter。本审计的「还原」一律指**功能与视觉等价重写**；内核用 LU 现有的 media_kit(libmpv)+AVPlayer 等价实现，不追求二进制级一致。审计日期 2026-11-20。

## 本轮进展（针对红圈标注的"缺失/部分"项）

| 红圈项 | 处理结果 | 落点 |
|---|---|---|
| OSD CPU/帧率 | ✅ 补帧率（mpv `estimated-vf-fps`）；CPU 占用无跨平台 API，未做 | emby_player_page.dart `_readFps` |
| 定时关闭 | ✅ **原本已实现**（此前审计误判）——`setSleepTimer` 已接线 | emby_player_panels.dart / controller |
| HDR 字幕亮度 | ✅ 新增设置项 + 自绘字幕描边/底板接线 | EmbySubtitleSettings.hdrBrightness |
| 外挂加载规则/字幕缓存 | ✅ 新增设置键 + 播放行为页 UI（仅同名/同文件夹全部/不自动加载） | settings_keys / emby_play_behavior_page |
| 自定义弹幕 API | ✅ 可配置域名，DanmakuApi 读取 | embyDanmakuApiBase / danmaku_api.dart |
| IPTV（M3U/M3U8/TXT + 订阅） | ✅ 新增完整 IPTV 页（解析/分组/订阅/更新/起播） | lu_iptv.dart / emby_iptv_page.dart |
| 视频笔记（截图+文字+跳时间点） | ✅ 新增播放器面板 + 本地存储 | emby_notes_sheet.dart / emby_video_notes.dart |
| 夸克 / Google Drive | ✅ 新增两家网盘（列目录+取直链） | lu_cloud_drive.dart / provider picker |
| Emby/Jellyfin 弹幕插件源 | 🟡 依赖服务端安装弹幕插件，Dart 侧无标准读取协议，未做 | — |
| 画中画弹幕 | ❌ 此前 PiP 弹幕层已下线，恢复需重做原生 PiP 叠加 | — |
| Plex / 飞牛 fnOS | 🟡 飞牛可用已有 WebDAV 接入；Plex 需独立 API client（大工程），未做 | — |
| Trakt / iCloud 同步 | ❌ 未做（Trakt 需 OAuth 注册；iCloud 是 iOS 专属，Flutter 跨端不适用） | — |
| 双内核 KSPlayer/mpv + AVPlayer | ✅ 等价：LU 用 mpv(libmpv)+AVPlayer，KSPlayer 是 Swift 专用无法移植 | media_kit path 依赖 |
| WebDAV / SMB / FTP | ✅ 原本已实现（此前审计为 🟡 是保守标注） | emby_server_form_page / vault_browse |

**构建验证**：全工程 `flutter analyze` 0 error；Android debug 构建见本轮记录。

## 一、信息架构 / 导航

| 功能 | SenPlayer | LU Emby 现状 | 证据 | 结论 |
|---|---|---|---|---|
| 可配置模块显隐/排序/默认首页 | 7 Tab 可配 | 本轮新增 SenTabPrefs + 模块管理面板 | sen_tab_prefs.dart / emby_tab_manager.dart | ✅ |
| 导航位置顶部/底部 | 支持 | 本轮新增 dock 配置 | sen_tab_prefs.dart | ✅ |
| 首页四段式 | 轮播/继续/接下来/最新/推荐 | 轮播+继续+接下来(本轮新增)+我的媒体+各库滑轨 | emby_page.dart `_HomeBodyState` | ✅ |
| 设置 14 分组 | 完整 | 我的页已有 内容/播放/画质性能/其他 四大组 + 全局设置页 | emby_res_pane.dart `EmbyMinePane` | 🟡 |

## 二、播放内核与解码

| 功能 | SenPlayer | LU Emby 现状 | 证据 | 结论 |
|---|---|---|---|---|
| 双内核 mpv + AVPlayer | KSPlayer/mpv + AVPlayer | media_kit(libmpv 本地定制) + AVPlayer | pubspec.yaml path:./media_kit；player_page | ✅ |
| 硬解/软解切换 | ✅ | 有「硬件解码」设置入口（自动） | emby_res_pane.dart / settings/player | ✅ |
| HDR/杜比/4K8K | ✅ | libmpv 原生支持 + 渲染后端设置 | player_page / settings/player | ✅ |
| 倍速/播放模式/记忆进度 | ✅ | 长按倍速 + 续播(watch_log) | player_page / emby_watch_log.dart | ✅ |
| 片头片尾自动跳过 | ✅ | 有 skip marks 服务 | emby_skip_marks.dart | ✅ |
| 画中画 PiP / 后台音频 | ✅ | iOS AV 原生 PiP + Android 系统 PiP + 后台音频 | pip_utils.dart / player_page | ✅ |
| OSD（时间/网速/电量） | ✅ | 顶栏状态行已有 时间/WiFi/网速/电量 | player_page `_topStatus` | ✅ |
| OSD（CPU/帧率） | 有 | 帧率已接 mpv `estimated-vf-fps`；CPU 无跨平台 API | player_page `_readFps` | 🟡 |
| 蓝光 ISO / ISO 分集 | ✅ | libmpv 可解 ISO，但无分集 UI | media_kit | 🟡 |
| 网络预缓存/预载下一集/302缓存 | ✅ | 有「播放缓存」设置 + 串流模式 | emby_stream_prefs.dart / settings | 🟡 |
| 定时关闭/系统媒体控制 | ✅ | 两者均已实现并接线 | controller `setSleepTimer` / player_page | ✅ |

## 三、字幕

| 功能 | SenPlayer | LU Emby 现状 | 证据 | 结论 |
|---|---|---|---|---|
| 内封/外挂字幕 | ✅ | 双内核均支持 | player_page | ✅ |
| 主/副双字幕 | ✅ | 已实现（简繁转换 + 副字幕层） | player_page `_SubtitleLayer` | ✅ |
| 在线字幕搜索 | ASSRT/OpenSubtitles/射手 | 有字幕整页搜索 | emby_subtitle_search_page.dart | ✅（源不同） |
| 简繁转换/样式/大小/颜色 | ✅ | 自绘字幕层全支持 | player_page 1156+ | ✅ |
| HDR 字幕亮度 | ✅ | 已实现（样式面板 + 自绘描边/底板） | EmbySubtitleSettings.hdrBrightness | ✅ |
| 外挂加载规则/字幕缓存 | ✅ | 三选一加载规则 + 缓存开关 | emby_play_behavior_page | ✅ |

## 四、弹幕

| 功能 | SenPlayer | LU Emby 现状 | 证据 | 结论 |
|---|---|---|---|---|
| 弹幕加载/协议 | 弹弹Play | dandanplay 自动匹配 + 本地 XML 导入 | emby_danmaku.dart | ✅ |
| 关键词屏蔽/位置/速度/显示区域 | ✅ | 有弹幕设置面板 | player_page 弹幕菜单 | ✅ |
| Emby/Jellyfin 弹幕插件 | ✅ | 服务端插件协议未标准化，Dart 侧未接 | — | 🟡 |
| 自定义弹幕 API | ✅ | 已可配置域名，DanmakuApi 读取 | embyDanmakuApiBase / danmaku_api.dart | ✅ |
| 画中画弹幕 | ✅ | 未见（画中画弹幕已下线） | player_page 注释 | ❌ |

## 五、投屏 / 资源协议 / 网盘

| 功能 | SenPlayer | LU Emby 现状 | 证据 | 结论 |
|---|---|---|---|---|
| AirPlay | ✅ | iOS AVRoutePicker 原生 | cast_service.dart | ✅ |
| DLNA 投屏 | ✅ | dlna_dart 依赖在，但未接入 Emby 播放链路 | pubspec / cast_service | 🟡 |
| WebDAV | ✅（含HTTPS/FTPS） | webdav_client 依赖 + 服务器表单 | pubspec / emby_server_form_page | ✅ |
| SMB / FTP | ✅（SMB2/3） | 服务器表单/扫描/浏览页有接入 | emby_scan_page / emby_vault_browse_page | 🟡 |
| Emby / Jellyfin | ✅ | 完整（本模块即 Emby） | emby_service.dart | ✅ |
| Plex / 飞牛 fnOS | ✅ | 未见于 Emby 模块 | — | ❌ |
| 网盘 115/123/百度/阿里/OneDrive/Dropbox | ✅ | 全部已实现 | lu_cloud_drive.dart | ✅ |
| 夸克 / Google Drive | ✅ | 缺失 | — | ❌ |
| 扫码登录/OAuth | ✅ | 115 扫码已实现，其余 token 粘贴 | lu_cloud_drive.dart | 🟡 |
| 服务器线路探测/切换 | ✅ | emby_line_probe.dart | emby_line_probe.dart | ✅ |

## 六、同步 / 记录 / 工具

| 功能 | SenPlayer | LU Emby 现状 | 证据 | 结论 |
|---|---|---|---|---|
| 观看记录/继续观看 | ✅ | emby_watch_log.dart + fetchResume | emby_watch_log.dart | ✅ |
| 视频笔记（截图+文字，跳转时间点） | ✅ | 已实现（本地 JSON + 截图落盘 + 跳时间点） | emby_notes_sheet.dart / emby_video_notes.dart | ✅ |
| Wi-Fi 传输（GCDWebUploader） | ✅ | 缺失 | — | ❌ |
| IPTV（M3U/M3U8/TXT+订阅） | ✅ | 已建专页：解析 / 分组 / 订阅 / 刷新 / 起播 | lu_iptv.dart / emby_iptv_page.dart | ✅ |
| Trakt 同步 | ✅ | 缺失 | — | ❌ |
| iCloud/CloudKit 同步 | ✅ | 缺失（Flutter 跨端不适用） | — | ❌(iOS专属，评估) |
| 私密空间/应用锁 | ✅ | VaultLock + EmbyVaultLockPage | vault_lock.dart | ✅ |
| 应用锁/Face ID | ✅ | 全局有 local_auth | pubspec local_auth | ✅ |
| 文件加密/解密 | ✅ | lu_media_vault.dart | lu_media_vault.dart | ✅ |
| 收藏/历史清除/标记已看 | ✅ | fetchFavorites + 记录页 | emby_records_pane.dart | ✅ |

## 七、缺失清单（可补齐，排除会员）

1. **DLNA 接入 Emby 播放链路**（dlna_dart 依赖已在，需设备发现 + 推送当前片源）
2. **Plex 媒体库前端**（飞牛 fnOS 可走已有 WebDAV）
3. **Wi-Fi 传输**（浏览器上传）
4. **Trakt 同步**（需 OAuth 注册）
5. **OSD CPU 占用**（无跨平台 API）
6. **蓝光 ISO 分集 UI**（libmpv 能解，缺前端）
7. **弹幕：Emby/Jellyfin 插件源 / PiP 弹幕**（前者依赖服务端协议，后者需原生 PiP 叠加）
8. **iCloud/CloudKit 同步**（iOS 专属，Flutter 跨端不适用）

> 夸克 / Google Drive、视频笔记、HDR 字幕亮度、帧率、自定义弹幕 API、IPTV 已在本轮补齐，从清单移除。

## 八、部分实现清单

- 设置 14 分组（现 4 大组 + 全局设置页，功能在但组织不同）
- SMB/FTP（有接入但走服务器表单，未做 SenPlayer 式文件树）
- 扫码登录（仅 115，其余 token 粘贴）
- 网络预缓存/预载下一集
- IPTV（全局解析能力在，Emby 模块无整合页）
- 蓝光 ISO（能解但无分集 UI）

## 九、会员相关（明确不做 ⛔）

- 5 个 StoreKit / 微信支付内购商品（永久 Pro iPhone/iPad/TV/Mac/移动）
- PRO 14 项权益门控
- 网盘投屏会员提示等付费引导

## 十、UI 交互 / 动效 / 播放器按钮

| 项目 | SenPlayer | LU Emby 本轮实现 | 落点 | 结论 |
|---|---|---|---|---|
| 按压反馈（内容变淡 + 轻缩放 + haptic） | iOS 原生全平台一致 | `KzPressable` 去掉 Android InkWell 分支，双端统一用 `KazumiMotion` 时长曲线，按下 tap 触感 | theme/ios_interaction.dart | ✅ |
| 动效时长/曲线统一 | 系统 spring | `KazumiMotion` instant 90 / fast 160 / base 240 / slow 320 / hero 520 + spring 过冲曲线 | utils/motion.dart | ✅ |
| Tab 选中态回弹 | spring | `_SubDockButton` 改用 `KzPressable` + `KazumiMotion.spring` | pages/emby/emby_page.dart | ✅ |
| 播放器裸按钮按压 | 轻触缩放 + haptic | `_PressScale` 按下 instant / 松手 base+spring，所有 `_CircleAction`/`_OutlineAction`/`_BareAction` 统一触感 | emby_player_page.dart | ✅ |
| 菜单行按压 | UIMenu 高亮 + 触感 | `_MenuPress` 加 `KazumiHaptics.tap()`，着色时长改 `KazumiMotion` | emby_player_popover.dart | ✅ |
| 进度条拖动触感 | 起拖/落点各一次 | `onDragStart` 与 `onTapSeek` 补 tap，落点仍走 `hapticProgress` 设置 | emby_player_page.dart | ✅ |
| 播放器按钮逐个显示/隐藏 | `kShowPlayerXxxButton` | `PlayerButtonPrefs` 18 个稳定 id，JSON 持久化 + revision 实时刷新 | services/emby/player_button_prefs.dart | ✅ |
| 按钮设置页 UI | 分组开关 + 恢复默认 | 顶栏/工具行/底栏三组 `KzSwitchTile`，「全部显示」可重置，播放/暂停禁用隐藏 | emby_player_buttons_page.dart | ✅ |
| 按钮隐藏后的间距 | 不留空档 | `_rowWithGaps` 只对实际构建的按钮插间隔 | emby_player_page.dart | ✅ |
| 设置入口 | 播放器更多 + 设置 | 更多→工具→「播放器按钮」；我的页→界面与模块→「播放器按钮」 | emby_player_panels.dart / emby_res_pane.dart | ✅ |
| 覆盖的按钮 | 播放/暂停/返回/上下集/快进快退/进度条/倍速/字幕/音轨/章节/播放列表/比例/全屏/截图/PiP/投屏/跳过片头片尾/锁定/分享/保存 | 18 项覆盖：返回·投屏·比例·重载·PiP·截图·倍速·信息·音轨·字幕·弹幕·更多·锁定·上/下一集·播放暂停·选集·进度条（章节/分享/保存走面板，无独立控制栏按钮） | 同上 | 🟡（等价实现） |

> 排除项不变：会员购买、内购、PRO 门控一律不移植。

---

_本文件随实施推进持续更新。_
