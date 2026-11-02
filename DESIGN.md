# LU 设计语言准则

> 一句话：**Pv 是唯一语言，Clay 只留按钮。**

历史上 `lib/` 里同时躺着四套界面语言（Clay 粘土块、Clay-Neu 拟物、Emby 自绘、
Pv iOS 白卡），每加一个页面都要重新选一次语言，同一页里也可能两种混着。
3.9.28 起收敛成一套。

---

## 一、分工

| 层 | 用什么 | 在哪 |
|---|---|---|
| **页面底座** | `PvColors.page(context)` | 每个 `Scaffold.backgroundColor`、`SysAppBar` 默认背景 |
| **容器与列表** | `PvGroup` / `PvRow` / `PvSectionHead` / `PvGroupLabel` | 设置、我的、下载、历史、搜索结果 |
| **卡片** | `PvColors.card(context)` + 16 圆角 | 下载卡、历史卡、资源库卡 |
| **文字** | `PvText.*`（pageTitle 34/w800、section 17/w700、rowTitle 15/w500） | 页内大标题、区块标题、行标题 |
| **强调与主操作** | `PvColors.blue` / `red` / `green` / `amber*` | 主要按钮、状态点、删除 |
| **底栏** | `KazumiTabBar`（玻璃胶囊，令牌已对齐 Pv `--dock`） | 全局唯一底栏 |
| **按下反馈** | 底色压深 + 1px 下沉，**不用渐变、不用高光边** | 所有可点行 |

只有一种例外：**播放器全屏层继续用自己的深色皮肤**。浮在视频上的控件需要厚实、
高对比，Pv 的白卡在视频上会碎成一片。

## 二、逐页对照

| 区域 | 3.9.27 之前 | 3.9.28 |
|---|---|---|
| 壳（底栏 / 内容底色 / 桌面侧栏） | Neu 中灰 + 拟态侧栏 | Pv 页面底色 + 白卡侧栏 |
| 我的 | Neu 外壳 + Pv 内容（一页两套） | 全 Pv |
| 设置 / 下载 / 历史 | Clay 粘土砖 | Pv 整卡 + 发丝线 |
| 推荐 | Neu 底色 + 拟态标签槽 | Pv 底色 + 淡蓝胶囊标签 |
| 追番 / 时间表 | Neu 底色 | Pv 底色 |
| 一起看 / Emby | Pv | Pv（未动） |
| 播放器内浮层 | 自家深色 | 自家深色（豁免） |

## 三、两条硬规矩

1. **同一个文件里不允许同时 import `clay.dart` 和 `emby_preview_style.dart`。**
   （`emby_style.dart` 是 Emby 的海报/图片件，不算界面语言。）
   这条能挡住 90% 的「顺手拿了个现成的」。
2. **新增页面从 `PvPageHead` + `PvGroup` 开始搭**，不要从 `Scaffold` + `Card` 开始。
   页面标题走 Pv 的 34/800，不要用 `Theme.textTheme.headline*`。

## 四、颜色令牌

浅色 / 深色成对定义在 `PvColors`，改主题不需要重新设计：

| 令牌 | 浅 | 深 | 用途 |
|---|---|---|---|
| `page` | `#F3F1F2` | `#151417` | 页面底 |
| `card` | `#FFFFFF` | `#1F1E22` | 卡片 / 分组 |
| `ink` | `#0B0B0F` | `#F2F2F5` | 主文字 |
| `ink2` | `#6B6B70` | `#A5A5AC` | 次级文字 |
| `ink3` | `#9A9AA0` | `#74747C` | 弱文字 |
| `hair` | `rgba(0,0,0,.075)` | `rgba(255,255,255,.08)` | 发丝线 |
| `blue` | `#007AFF` | 同 | 强调 / 主操作 |
| `subCap` / `subInk` | `#38548021` / `#2F4E7A` | `#FFFFFF1F` / `#A9C0E4` | 选中胶囊 |

## 五、底盘

- 全局 `scaffoldBackgroundColor` 已对齐 Pv（`immersive_theme.dart`）。
- `SysAppBar` 默认背景 = `PvColors.page`，标题 = 17/w700/`ink`。
- 卡片主题默认色 = `PvColors.card`，所以 `Card()` 不写颜色就是对的。

## 六、设置类页面的唯一入口

设置页有二十多个二级页，全部经由 `bean/settings/settings_list.dart` 里的
`SettingsList / SettingsSection / SettingsTile / SettingsSliderTile /
SettingsCategoryTile` 落地。这一层已经是 Pv（整卡 + 发丝线 + 15 内边距 +
50 行高 + `PvSwitch` + 蓝色对勾），**新加设置项不要自己画卡片**，否则又会
出现「一页里两套材质」。

- 分组标题用 `SettingsSection(title:)`，它已经套好 11.5/w600 的灰标签。
- 开关一律 `SettingsTile.switchTile`（内部是 iOS 绿开关），单选一律
  `SettingsRadioSection` + `SettingsTile.radioTile`。
- `SettingsDetailScaffold` 顶栏同样是 `SysAppBar`，所以二级页不需要自备 AppBar。

## 七、Emby 播放器里的例外

全屏播放器浮层保持深色（Pv 白卡浮在画面上会碎），但**横屏右侧浮层**按演示
视频是白卡：`showEmbyPlayerSheet` 会在横屏切到浅色令牌。字幕面板
（`buildEmbySubtitlePanel`）在横屏下不画标题栏，直接从「主字幕」开始——这是
唯一一处「长按/点按以外没有关闭按钮」的面板，靠点空白收起。
