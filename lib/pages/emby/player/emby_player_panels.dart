import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/emby/player/emby_player_controller.dart';
import 'package:XL/pages/emby/player/emby_player_popover.dart';

/// 播放器内的面板。
///
/// 对应 Rex 的这几个文件：
///   * `PlayerBottomPickerView.swift` —— 底部选择器
///   * `PlayerEpisodeCollectionView.swift` —— 选集
///   * `PlayerPresentationSettingsSheetView.swift` —— 显示设置
///   * `PlayerPlaybackSettingsView.swift` —— 播放 / 解码 / 顺序 / 片头片尾
///   * `PlayerSleepTimerView.swift` —— 定时关闭
///
/// 播放器是全黑环境，面板不用主题色板，固定深色，避免浅色主题下
/// 突然弹出一个白板子把人晃到。

/// 面板配色。
///
/// 播放器是深色环境，但菜单刻意做成浅色——这是 iOS 系统菜单（UIMenu）在
/// 视频播放器里的样子：浅色材质浮在画面上，一眼就能和「画面」分开。深色卡片
/// 压在暗场画面里会糊成一片，反而看不清。
const Color _ink = Color(0xFF101013);
const Color _inkSecondary = Color(0xFF6B6B70);
const Color _inkTertiary = Color(0xFF9A9AA0);

/// 打开一个播放器面板。
///
/// 统一走 [showEmbyPopover]：从触发按钮的位置长出来一张 iOS 菜单，不再从底部
/// 升起大抽屉。参数保持不变，页面侧不用改。
Future<T?> showEmbyPlayerSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  bool isDesktop = false,
  bool scrollable = true,
  bool hideHeaderWhenWide = false,
}) {
  final Size size = MediaQuery.sizeOf(context);
  // 没有锚点（极少数从代码直接打开的路径）就贴着右下角，别飞到屏幕正中。
  final Rect anchor =
      embyLastAnchor ??
      Rect.fromLTWH(size.width - 64, size.height - 120, 48, 48);
  return showEmbyPopover<T>(
    context,
    anchor: anchor,
    header: hideHeaderWhenWide ? null : title,
    // 竖屏手机窄，菜单跟着收窄一点，不然左右都没边距。
    width: size.width < 420 ? (size.width - 48).clamp(220.0, 300.0) : 288,
    builder: builder,
  );
}

/// 分组标题：灰底居中，iOS 菜单的分组头就长这样。
class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => EmbyMenuHeader(label);
}

/// 一行可选项 / 动作。
class _PanelRow extends StatelessWidget {
  const _PanelRow({
    required this.title,
    this.subtitle,
    this.icon,
    this.selected = false,
    this.chevron = false,
    this.destructive = false,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final bool destructive;

  /// 右侧 `>`：点了会再弹一层菜单。普通动作项不要挂，iOS 菜单里不是每行都带箭头。
  final bool chevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return EmbyMenuRow(
      label: title,
      detail: subtitle,
      icon: icon,
      checked: selected,
      chevron: chevron,
      destructive: destructive,
      onTap: onTap,
    );
  }
}

/// 一组横向选项（画面比例这种）：菜单里改成竖排，选中打勾。
class _SegmentedRow extends StatelessWidget {
  const _SegmentedRow({
    required this.options,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < options.length; i++)
          EmbyMenuRow(
            label: options[i],
            checked: i == selectedIndex,
            onTap: () => onSelect(i),
          ),
      ],
    );
  }
}

/// 带 −/＋ 的调节行。菜单里不做弹窗，就地调，调完还留在菜单里继续看画面。
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: embyMenuLine, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: _ink, fontSize: 15),
            ),
          ),
          _StepButton(icon: Icons.remove_rounded, onTap: onMinus),
          SizedBox(
            width: 62,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _ink,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _StepButton(icon: Icons.add_rounded, onTap: onPlus),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: const Color(0x11000000),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 17, color: _ink),
      ),
    );
  }
}

// ---------------------------------------------------------------- 具体面板

/// 「更多」总面板：播放设置 + 工具。
class EmbyMorePanelActions {
  const EmbyMorePanelActions({
    required this.onDecode,
    required this.onPlaybackMode,
    required this.onIntroOutro,
    required this.onSleep,
    required this.onBackground,
    required this.onProgress,
    this.episodeCount = 0,
    this.decodeLabel = '硬解',
    this.playbackModeLabel = '顺序播放',
    this.sleepLabel = '不启用',
    this.background = false,
    this.progressAlways = false,
  });

  final VoidCallback onDecode;
  final VoidCallback onPlaybackMode;
  final VoidCallback onIntroOutro;
  final VoidCallback onSleep;
  final VoidCallback onBackground;
  final VoidCallback onProgress;
  final int episodeCount;
  final String decodeLabel;
  final String playbackModeLabel;
  final String sleepLabel;
  final bool background;
  final bool progressAlways;
}

Widget buildEmbyMorePanel(BuildContext context, EmbyMorePanelActions a) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _GroupTitle('播放设置'),
      _PanelRow(
        title: '解码',
        subtitle: a.decodeLabel,
        chevron: true,
        onTap: a.onDecode,
      ),
      _PanelRow(
        title: '顺序播放',
        subtitle: a.playbackModeLabel,
        chevron: true,
        onTap: a.onPlaybackMode,
      ),
      _PanelRow(title: '片头片尾', chevron: true, onTap: a.onIntroOutro),
      _PanelRow(
        title: '定时关闭',
        subtitle: a.sleepLabel,
        chevron: true,
        onTap: a.onSleep,
      ),
      // 「媒体信息」不再放这里：顶栏已经有一枚 info 按钮，重复入口只会
      // 让人以为点开的是两份不同的数据。
      const _GroupTitle('工具'),
      _PanelRow(
        title: '后台音频',
        subtitle: a.background ? '继续播放声音' : '随画面一起暂停',
        selected: a.background,
        onTap: a.onBackground,
      ),
      _PanelRow(
        title: '进度条常显',
        selected: a.progressAlways,
        onTap: a.onProgress,
      ),
      const SizedBox(height: 8),
    ],
  );
}

/// 选集面板。
Widget buildEmbyEpisodePanel(
  BuildContext context, {
  required List<EmbyItem> episodes,
  required int currentIndex,
  required ValueChanged<int> onSelect,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (int i = 0; i < episodes.length; i++)
        _EpisodeRow(
          item: episodes[i],
          index: i,
          selected: i == currentIndex,
          onTap: () => onSelect(i),
        ),
      const SizedBox(height: 8),
    ],
  );
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.item,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final EmbyItem item;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double ratio = item.watchedRatio;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
        decoration: BoxDecoration(
          color: selected ? embyMenuChecked : Colors.transparent,
          border: const Border(
            bottom: BorderSide(color: embyMenuLine, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: selected
                  ? const Icon(Icons.check_rounded, size: 17, color: _ink)
                  : Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: _inkTertiary,
                        fontSize: 12.5,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _ink,
                      fontSize: 15,
                      height: 1.25,
                      fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                  if (ratio > 0.01) ...[
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: ratio.clamp(0, 1),
                        minHeight: 2.5,
                        backgroundColor: const Color(0x1A000000),
                        valueColor: const AlwaysStoppedAnimation<Color>(_ink),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 倍速面板。Rex 是「自定义」滚动列表，0.5× 到 8.0×。
const List<double> _speeds = <double>[
  0.5,
  0.75,
  1.0,
  1.25,
  1.5,
  1.75,
  2.0,
  2.5,
  3.0,
  4.0,
  8.0,
];

String embySpeedLabel(double value) {
  if (value == value.roundToDouble()) return '${value.toInt()}';
  return value.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
}

Widget buildEmbySpeedPanel({
  required double current,
  required ValueChanged<double> onSelect,
}) {
  final int index = _speeds.indexOf(current).clamp(0, _speeds.length - 1);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (int i = 0; i < _speeds.length; i++)
        _PanelRow(
          title: '${embySpeedLabel(_speeds[i])}×',
          selected: i == index,
          onTap: () => onSelect(_speeds[i]),
        ),
      const SizedBox(height: 8),
    ],
  );
}

/// 音轨面板：完整编码信息 + 关闭音频 + 音频增强。
Widget buildEmbyAudioPanel({
  required List<AudioTrack> tracks,
  required AudioTrack? current,
  required double gain,
  required VoidCallback onDisableAudio,
  required ValueChanged<AudioTrack> onSelect,
  required VoidCallback onEnhance,
}) {
  final String? currentId = current?.id;
  final bool audioOff =
      currentId == null || currentId == 'no' || currentId == 'none';
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _PanelRow(title: '关闭音频', selected: audioOff, onTap: onDisableAudio),
      if (tracks.isEmpty)
        Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(
            '这条视频只有一条音轨',
            style: TextStyle(color: _inkSecondary, fontSize: 13),
          ),
        ),
      for (final track in tracks)
        _PanelRow(
          title: _audioTitle(track),
          subtitle: _audioDetail(track),
          selected: !audioOff && track.id == currentId,
          onTap: () => onSelect(track),
        ),
      _PanelRow(
        title: '音频增强',
        subtitle: gain <= 1.001 ? '关闭' : '${embyGainLabel(gain)}×',
        chevron: true,
        onTap: onEnhance,
      ),
      const SizedBox(height: 8),
    ],
  );
}

String _audioTitle(AudioTrack track) {
  final title = track.title;
  if (title != null && title.trim().isNotEmpty) return title.trim();
  final lang = _languageName(track.language);
  if (lang.isNotEmpty) return lang;
  if ((track.codec ?? '').trim().isNotEmpty) {
    return (track.codec!).trim().toUpperCase();
  }
  return '音轨 ${track.id}';
}

String _audioDetail(AudioTrack track) {
  final parts = <String>[];
  final lang = _languageName(track.language);
  if (lang.isNotEmpty) parts.add(lang);
  if ((track.codec ?? '').trim().isNotEmpty) {
    parts.add((track.codec!).trim().toUpperCase());
  }
  if (track.samplerate != null && track.samplerate! > 0) {
    parts.add('${(track.samplerate! / 1000).toStringAsFixed(1)}kHz');
  }
  if (track.channelscount != null && track.channelscount! > 0) {
    parts.add('${track.channelscount}ch');
  } else if (track.channels != null && track.channels!.isNotEmpty) {
    parts.add(track.channels!);
  }
  if (track.bitrate != null && track.bitrate! > 0) {
    parts.add('${(track.bitrate! / 1000).toStringAsFixed(1)}kbps');
  }
  return parts.join(' · ');
}

/// 音频增强倍率。
const List<double> _gains = <double>[1.0, 1.5, 3.0, 5.0, 10.0];

String embyGainLabel(double value) =>
    value == 1.0 ? '1' : value.toStringAsFixed(1);

Widget buildEmbyGainPanel({
  required double current,
  required ValueChanged<double> onSelect,
}) {
  final int index = _gains.indexOf(current).clamp(0, _gains.length - 1);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (int i = 0; i < _gains.length; i++)
        _PanelRow(
          title: _gains[i] == 1.0 ? '关闭' : '${embyGainLabel(_gains[i])}×',
          subtitle: _gains[i] == 1.0
              ? '原声'
              : '放大 ${embyGainLabel(_gains[i])} 倍',
          selected: i == index,
          onTap: () => onSelect(_gains[i]),
        ),
      const SizedBox(height: 8),
    ],
  );
}

/// 字幕面板（按演示视频）：主字幕 / 副字幕（各自展开选轨）+ 字幕搜索 +
/// 本地导入 + 字幕设置 + 永久禁用。
///
/// 主/副字幕是就地展开的单选列表，选中项左侧打勾，跟视频里一致。
Widget buildEmbySubtitlePanel({
  required List<SubtitleTrack> tracks,
  required SubtitleTrack? current,
  required SubtitleTrack? secondary,
  required ValueChanged<SubtitleTrack> onSelect,
  required ValueChanged<SubtitleTrack> onSelectSecondary,
  required VoidCallback onSettings,
  required VoidCallback onDisableForever,
  required VoidCallback onSearch,
  required VoidCallback onImport,
}) {
  // 展开状态必须放在 StatefulBuilder 外面：放在里面每次 setState 重建都会
  // 重新初始化成「主字幕」，点「副字幕」会像没反应一样弹回去。
  var expanded = _SubtitleSection.primary;
  return StatefulBuilder(
    builder: (context, setState) {
      Widget section(
        String title, {
        required _SubtitleSection which,
        required SubtitleTrack? selected,
        required ValueChanged<SubtitleTrack> onPick,
        required bool withDisable,
      }) {
        final bool open = expanded == which;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SubExpandRow(
              title: title,
              open: open,
              onTap: () => setState(() {
                expanded = open ? _SubtitleSection.none : which;
              }),
            ),
            if (open) ...[
              _SubOptionRow(
                label: '禁用',
                checked: selected == null || selected.id == 'no',
                onTap: () => onPick(SubtitleTrack.no()),
              ),
              if (tracks.isEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 10, 20, 6),
                  child: Text(
                    '这条视频没有内封字幕',
                    style: TextStyle(color: _inkSecondary, fontSize: 12.5),
                  ),
                ),
              for (final track in tracks)
                _SubOptionRow(
                  label: track.title?.trim().isNotEmpty == true
                      ? track.title!.trim()
                      : _languageName(track.language),
                  // 视频里这一行只有名字，没有「简体中文 · SRT」这种副标题。
                  checked: track.id == selected?.id && selected?.id != 'no',
                  onTap: () => onPick(track),
                ),
            ],
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          section(
            '主字幕',
            which: _SubtitleSection.primary,
            selected: current,
            onPick: onSelect,
            withDisable: true,
          ),
          section(
            '副字幕',
            which: _SubtitleSection.secondary,
            selected: secondary,
            onPick: onSelectSecondary,
            withDisable: true,
          ),
          // 分界：上面是选轨，下面是动作。视频里这两组之间有一条淡线。
          Container(
            height: 0.8,
            margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            color: _ink.withValues(alpha: 0.08),
          ),
          _PanelRow(title: '字幕搜索', chevron: true, onTap: onSearch),
          _PanelRow(title: '本地导入', chevron: true, onTap: onImport),
          _PanelRow(title: '字幕设置', chevron: true, onTap: onSettings),
          _PanelRow(
            title: '永久禁用',
            chevron: true,
            destructive: true,
            onTap: onDisableForever,
          ),
          const SizedBox(height: 8),
        ],
      );
    },
  );
}

enum _SubtitleSection { none, primary, secondary }

/// 可展开的分组标题（视频里标题左边是向下箭头）。
class _SubExpandRow extends StatelessWidget {
  const _SubExpandRow({
    required this.title,
    required this.open,
    required this.onTap,
  });

  final String title;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: embyMenuLine, width: 0.5)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Icon(
                open
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_right_rounded,
                size: 18,
                color: _inkSecondary,
              ),
            ),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单选行：选中在左边打勾（视频里的样子）。
///
/// 视频里这一行只有名字和一个勾，没有「语言 · 编码」的副标题，行高也一致；
/// 副标题会让每一项高矮不一，读起来像列表而不是选项。
class _SubOptionRow extends StatelessWidget {
  const _SubOptionRow({
    required this.label,
    required this.checked,
    required this.onTap,
  });

  final String label;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.fromLTRB(38, 8, 14, 8),
        decoration: BoxDecoration(
          color: checked ? embyMenuChecked : Colors.transparent,
          border: const Border(
            bottom: BorderSide(color: embyMenuLine, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: checked
                  ? const Icon(Icons.check_rounded, size: 16, color: _ink)
                  : null,
            ),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _ink,
                  fontSize: 15,
                  fontWeight: checked ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 字幕设置：延迟 / 垂直偏移 / 大小缩放 / 不透明度。
Widget buildEmbySubtitleSettingsPanel({
  required EmbySubtitleSettings settings,
  required ValueChanged<EmbySubtitleSettings> onChanged,
  VoidCallback? onReset,
  bool subtitleActive = true,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // 没挂字幕时调这几项是看不到任何变化的，容易让人以为「功能没接」。
      if (!subtitleActive)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
          child: Text(
            '当前没有显示字幕。先在「主字幕」里选一条，这里的调整才有画面可看。',
            style: TextStyle(color: _inkTertiary, fontSize: 12, height: 1.45),
          ),
        ),
      _StepperRow(
        label: '延迟显示',
        value:
            '${settings.delay >= 0 ? '+' : ''}${settings.delay.toStringAsFixed(1)}s',
        onMinus: () => onChanged(
          settings.copyWith(delay: (settings.delay - 0.5).clamp(-10, 10)),
        ),
        onPlus: () => onChanged(
          settings.copyWith(delay: (settings.delay + 0.5).clamp(-10, 10)),
        ),
      ),
      _StepperRow(
        label: '垂直偏移',
        value: '${settings.verticalOffset.round()}',
        onMinus: () => onChanged(
          settings.copyWith(
            verticalOffset: (settings.verticalOffset - 5).clamp(0, 100),
          ),
        ),
        onPlus: () => onChanged(
          settings.copyWith(
            verticalOffset: (settings.verticalOffset + 5).clamp(0, 100),
          ),
        ),
      ),
      _StepperRow(
        label: '大小缩放',
        value: '${settings.scale.toStringAsFixed(2)}×',
        onMinus: () => onChanged(
          settings.copyWith(scale: (settings.scale - 0.1).clamp(0.5, 2)),
        ),
        onPlus: () => onChanged(
          settings.copyWith(scale: (settings.scale + 0.1).clamp(0.5, 2)),
        ),
      ),
      _StepperRow(
        label: '不透明度',
        value: '${(settings.opacity * 100).round()}%',
        onMinus: () => onChanged(
          settings.copyWith(opacity: (settings.opacity - 0.1).clamp(0.1, 1)),
        ),
        onPlus: () => onChanged(
          settings.copyWith(opacity: (settings.opacity + 0.1).clamp(0.1, 1)),
        ),
      ),
      if (onReset != null) ...[
        Container(
          height: 0.8,
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          color: _ink.withValues(alpha: 0.08),
        ),
        _PanelRow(title: '重置为默认', destructive: true, onTap: onReset),
      ],
      const SizedBox(height: 8),
    ],
  );
}

String _languageName(String? code) {
  if (code == null || code.isEmpty) return '';
  final key = code.toLowerCase().split(RegExp(r'[-,;]')).first.trim();
  return switch (key) {
    'zh' || 'chi' || 'zho' || 'zh-cn' || 'zh-hans' => '简体中文',
    'zh-tw' || 'zh-hk' || 'zh-hant' => '繁体中文',
    'ja' || 'jpn' => '日语',
    'en' || 'eng' => '英语',
    'ko' || 'kor' => '韩语',
    'fr' || 'fra' || 'fre' => '法语',
    'de' || 'deu' || 'ger' => '德语',
    'es' || 'spa' => '西班牙语',
    'ru' || 'rus' => '俄语',
    'it' || 'ita' => '意大利语',
    'pt' || 'por' => '葡萄牙语',
    'th' || 'tha' => '泰语',
    'vi' || 'vie' => '越南语',
    'und' => '未标注',
    _ => code,
  };
}

/// 画面比例面板：10 项，含具体比例档。
class EmbyAspectOption {
  const EmbyAspectOption(this.label, this.fit, this.ratio);
  final String label;
  final BoxFit fit;
  final double? ratio; // 非 null 时按该比例裁切
}

const List<EmbyAspectOption> embyAspectOptions = <EmbyAspectOption>[
  EmbyAspectOption('适应屏幕', BoxFit.contain, null),
  EmbyAspectOption('裁剪全屏', BoxFit.cover, null),
  EmbyAspectOption('拉伸填满', BoxFit.fill, null),
  EmbyAspectOption('4:3', BoxFit.cover, 4 / 3),
  EmbyAspectOption('5:4', BoxFit.cover, 5 / 4),
  EmbyAspectOption('16:9', BoxFit.cover, 16 / 9),
  EmbyAspectOption('16:10', BoxFit.cover, 1.6),
  EmbyAspectOption('18:9', BoxFit.cover, 2.0),
  EmbyAspectOption('21:9', BoxFit.cover, 21 / 9),
  EmbyAspectOption('2.39:1', BoxFit.cover, 2.39),
];

Widget buildEmbyAspectPanel({
  required int current,
  required ValueChanged<int> onSelect,
}) {
  return _SegmentedRow(
    options: [for (final o in embyAspectOptions) o.label],
    selectedIndex: current.clamp(0, embyAspectOptions.length - 1),
    onSelect: onSelect,
  );
}

/// 解码模式面板。
Widget buildEmbyDecodePanel({
  required EmbyDecodeMode current,
  required ValueChanged<EmbyDecodeMode> onSelect,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final mode in EmbyDecodeMode.values)
        _PanelRow(
          title: mode.label,
          selected: mode == current,
          onTap: () => onSelect(mode),
        ),
      const SizedBox(height: 8),
    ],
  );
}

/// 播放模式面板。
Widget buildEmbyPlaybackModePanel({
  required EmbyPlaybackMode current,
  required ValueChanged<EmbyPlaybackMode> onSelect,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final mode in EmbyPlaybackMode.values)
        _PanelRow(
          title: mode.label,
          selected: mode == current,
          onTap: () => onSelect(mode),
        ),
      const SizedBox(height: 8),
    ],
  );
}

/// 片头片尾面板。
Widget buildEmbyIntroOutroPanel({
  required bool introSkip,
  required bool outroSkip,
  required VoidCallback onMarkIntro,
  required VoidCallback onMarkOutro,
  required ValueChanged<bool> onIntroChanged,
  required ValueChanged<bool> onOutroChanged,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _PanelRow(
        icon: Icons.bookmark_add_outlined,
        title: '标记当前进度为片头',
        onTap: onMarkIntro,
      ),
      _PanelRow(
        icon: Icons.bookmark_outline_rounded,
        title: '标记当前进度为片尾',
        onTap: onMarkOutro,
      ),
      // 开关项用菜单勾位表示状态：行首出现对号即为开启，点一下切换。
      _PanelRow(
        icon: Icons.skip_next_rounded,
        title: '自动跳过片头',
        subtitle: introSkip ? '已开启' : '关闭',
        selected: introSkip,
        onTap: () => onIntroChanged(!introSkip),
      ),
      _PanelRow(
        icon: Icons.skip_next_rounded,
        title: '自动跳过片尾',
        subtitle: outroSkip ? '已开启' : '关闭',
        selected: outroSkip,
        onTap: () => onOutroChanged(!outroSkip),
      ),
      const SizedBox(height: 8),
    ],
  );
}

/// 定时关闭面板。
const List<int> _sleepOptions = <int>[
  0, // 不启用
  -1, // 播完当前后停止
  5, 10, 20, 30, 45, 60, 90, 120, 180,
];

String embySleepLabel(int mode) {
  if (mode == 0) return '不启用';
  if (mode == -1) return '播完当前视频';
  return '$mode 分钟后';
}

Widget buildEmbySleepPanel({
  required int current,
  required ValueChanged<int> onSelect,
}) {
  final index = _sleepOptions
      .indexOf(current)
      .clamp(0, _sleepOptions.length - 1);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (int i = 0; i < _sleepOptions.length; i++)
        _PanelRow(
          title: embySleepLabel(_sleepOptions[i]),
          selected: i == index,
          onTap: () => onSelect(_sleepOptions[i]),
        ),
      const SizedBox(height: 8),
    ],
  );
}

/// 章节面板。
Widget buildEmbyChapterPanel({
  required List<EmbyChapter> chapters,
  required Duration current,
  required ValueChanged<Duration> onSelect,
}) {
  if (chapters.isEmpty) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Text(
        '这条视频没有章节信息',
        style: TextStyle(color: _inkSecondary, fontSize: 13),
      ),
    );
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final c in chapters)
        _PanelRow(
          title: c.name,
          subtitle: _fmtDuration(c.start),
          selected:
              current >= c.start &&
              (chapters.last == c || current < _nextChapterStart(chapters, c)),
          onTap: () => onSelect(c.start),
        ),
      const SizedBox(height: 8),
    ],
  );
}

Duration _nextChapterStart(List<EmbyChapter> chapters, EmbyChapter c) {
  final i = chapters.indexOf(c);
  if (i < 0 || i + 1 >= chapters.length) return const Duration(days: 365);
  return chapters[i + 1].start;
}

/// 播放信息面板（Rex 的 `player.forward.statistics`）。
Widget buildEmbyInfoPanel({
  required String title,
  required String subtitle,
  required String resolution,
  required String decode,
  required String modeLabel,
  required String sleepLabel,
  required int chapterCount,
  required Duration position,
  required Duration duration,
  required Duration buffer,
  required double speed,
  required String streamUrl,
  String streamMode = '',
}) {
  final rows = <(String, String)>[
    ('标题', title),
    if (subtitle.isNotEmpty) ('副标题', subtitle),
    ('分辨率', resolution.isEmpty ? '未知' : resolution),
    ('解码', decode),
    if (streamMode.isNotEmpty) ('串流', streamMode),
    ('播放模式', modeLabel),
    ('定时关闭', sleepLabel),
    ('章节', chapterCount > 0 ? '$chapterCount 个' : '无'),
    ('进度', '${_fmtDuration(position)} / ${_fmtDuration(duration)}'),
    ('已缓冲', _fmtDuration(buffer)),
    ('速度', '${speed.toStringAsFixed(2)}×'),
    ('地址', streamUrl),
  ];
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (label, value) in rows)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 7, 20, 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  label,
                  style: TextStyle(color: _inkTertiary, fontSize: 12.5),
                ),
              ),
              Expanded(
                child: SelectableText(
                  value,
                  style: TextStyle(color: _ink, fontSize: 12.5, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 12),
    ],
  );
}

String _fmtDuration(Duration d) {
  final int h = d.inHours;
  final int m = d.inMinutes.remainder(60);
  final int s = d.inSeconds.remainder(60);
  final String mm = m.toString().padLeft(2, '0');
  final String ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}
