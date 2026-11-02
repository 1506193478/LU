import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/emby/player/emby_player_controller.dart';
import 'package:XL/theme/rex_design.dart';

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

/// 面板配色可以切换：
///   * 竖屏（底部抽屉）保持深色，跟播放器一体；
///   * 横屏（画面右侧浮层）按演示视频做成**白色卡片**，深墨字。
/// 面板是模态的，同一时刻只有一个，所以用一个静态开关就够了。
bool _panelLight = false;

Color get _sheetBg =>
    _panelLight ? const Color(0xFFFFFFFF) : const Color(0xFF16161A);
Color get _sheetBgRaised =>
    _panelLight ? const Color(0xFFFFFFFF) : const Color(0xFF1F1F24);
Color get _ink =>
    _panelLight ? const Color(0xFF0B0B0F) : const Color(0xFFF4F4F7);
Color get _inkSecondary =>
    _panelLight ? const Color(0xFF6B6B70) : const Color(0xFFA2A2AC);
Color get _inkTertiary =>
    _panelLight ? const Color(0xFF9A9AA0) : const Color(0xFF6E6E78);
Color get _accent =>
    _panelLight ? const Color(0xFF0B0B0F) : const Color(0xFFFFFFFF);
Color get _accentInk =>
    _panelLight ? const Color(0xFFFFFFFF) : const Color(0xFF101013);

/// 打开一个播放器面板。
Future<T?> showEmbyPlayerSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  bool isDesktop = false,
  bool scrollable = true,
  bool hideHeaderWhenWide = false,
}) {
  final Size size = MediaQuery.sizeOf(context);
  final bool desktop = isDesktop || size.width >= 900;

  // 演示视频里播放器是横屏，所有面板都是「画面右侧的白色圆角浮层」，
  // 不是从底部升起来的。竖屏手机还是用底部抽屉，不然浮层会挤得没法看。
  final bool landscape = size.width > size.height;
  _panelLight = landscape;

  Widget shell(BuildContext ctx) {
    final bool wide = desktop || landscape;
    final Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!wide)
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: _inkTertiary.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        // 字幕面板在横屏浮层里不画标题栏——演示视频里那张卡片是直接从
        // 「主字幕」开始的，多一行「字幕」+关闭键就不像了。
        if (!(wide && hideHeaderWhenWide))
          Padding(
            padding: EdgeInsets.fromLTRB(20, wide ? 18 : 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: _ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                _SheetCloseButton(onTap: () => Navigator.of(ctx).maybePop()),
              ],
            ),
          ),
        Flexible(
          child: scrollable
              ? SingleChildScrollView(
                  padding: EdgeInsets.only(
                    bottom: wide ? 20 : 12,
                    top: 4,
                  ),
                  child: builder(ctx),
                )
              : builder(ctx),
        ),
      ],
    );

    if (wide) {
      return Material(
        color: _sheetBgRaised,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 560),
          child: body,
        ),
      );
    }
    return Material(
      color: _sheetBg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          child: body,
        ),
      ),
    );
  }

  // 横屏：贴在画面右侧的浮层，右上角有关闭按钮，点空白处收起。
  if (landscape) {
    final double maxHeight =
        (size.height - 54 - 92).clamp(240.0, size.height);
    return showDialog<T>(
      context: context,
      barrierColor: const Color(0x55000000),
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(ctx).maybePop(),
            ),
          ),
          // 高度按内容走，不再从 top 拉到 bottom——字幕设置只有四行，
          // 拉满会剩一大片空白（截图里那块红框）。
          Positioned(
            right: 14,
            top: 54,
            width: 300,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Material(
                color: _sheetBgRaised,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: shell(ctx),
              ),
            ),
          ),
        ],
      ),
    );
  }
  if (desktop) {
    return showDialog<T>(
      context: context,
      barrierColor: const Color(0xAA000000),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: shell(ctx),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x88000000),
    builder: shell,
  );
}

class _SheetCloseButton extends StatelessWidget {
  const _SheetCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RexPressable(
      onTap: onTap,
      scale: 0.9,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Center(
          child: Icon(Icons.close_rounded, size: 19, color: _inkSecondary),
        ),
      ),
    );
  }
}

/// 分组小标题。
class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(
        label,
        style: TextStyle(
          color: _inkTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// 一行可选项。
class _PanelRow extends StatelessWidget {
  const _PanelRow({
    required this.title,
    this.subtitle,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color fg = selected ? _accent : _ink;
    return RexPressable(
      onTap: onTap,
      scale: 0.99,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? _ink.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 14.5,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _inkTertiary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_rounded, size: 18, color: _accent),
            ] else if (onTap != null) ...[
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: _inkTertiary),
            ],
          ],
        ),
      ),
    );
  }
}

/// 一组横向选项（倍速、画面比例这种）。
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (int i = 0; i < options.length; i++)
            RexPressable(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: i == selectedIndex
                      ? _accent
                      : _ink.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  options[i],
                  style: TextStyle(
                    color: i == selectedIndex ? _accentInk : _ink,
                    fontSize: 13,
                    fontWeight: i == selectedIndex
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 带 −/＋ 步进器的设置面板。
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
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _ink.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: _ink, fontSize: 14),
            ),
          ),
          RexPressable(
            onTap: onMinus,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _ink.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(Icons.remove_rounded, size: 18, color: _ink),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              width: 64,
              child: Text(
                value,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          RexPressable(
            onTap: onPlus,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _ink.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(Icons.add_rounded, size: 18, color: _ink),
              ),
            ),
          ),
        ],
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
    required this.onInfo,
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
  final VoidCallback onInfo;
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
        icon: Icons.hardware_rounded,
        title: '解码',
        subtitle: a.decodeLabel,
        onTap: a.onDecode,
      ),
      _PanelRow(
        icon: Icons.playlist_play_rounded,
        title: '顺序播放',
        subtitle: a.playbackModeLabel,
        onTap: a.onPlaybackMode,
      ),
      _PanelRow(
        icon: Icons.skip_next_rounded,
        title: '片头片尾',
        onTap: a.onIntroOutro,
      ),
      const _GroupTitle('工具'),
      _PanelRow(
        icon: Icons.timer_rounded,
        title: '定时关闭',
        subtitle: a.sleepLabel,
        onTap: a.onSleep,
      ),
      _PanelRow(
        icon: Icons.info_outline_rounded,
        title: '媒体信息',
        onTap: a.onInfo,
      ),
      _PanelRow(
        icon: Icons.headphones_rounded,
        title: '后台音频',
        subtitle: a.background ? '已开启' : '关闭',
        onTap: a.onBackground,
      ),
      _PanelRow(
        icon: Icons.linear_scale_rounded,
        title: '进度条常显',
        subtitle: a.progressAlways ? '已开启' : '关闭',
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
    return RexPressable(
      onTap: onTap,
      scale: 0.99,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _ink.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? _accent : _inkTertiary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 8),
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
                      color: selected ? _accent : _ink,
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (ratio > 0.01) ...[
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: ratio.clamp(0, 1),
                        minHeight: 2.5,
                        backgroundColor: _ink.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          selected ? _accent : _inkSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.graphic_eq_rounded, size: 16, color: _accent),
              ),
          ],
        ),
      ),
    );
  }
}

/// 倍速面板。Rex 是「自定义」滚动列表，0.5× 到 8.0×。
const List<double> _speeds = <double>[
  0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0, 8.0,
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
      _PanelRow(
        title: '关闭音频',
        selected: audioOff,
        onTap: onDisableAudio,
      ),
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
        icon: Icons.graphic_eq_rounded,
        title: '音频增强',
        subtitle: gain <= 1.001 ? '关闭' : '${embyGainLabel(gain)}×',
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
          subtitle: _gains[i] == 1.0 ? '原声' : '放大 ${embyGainLabel(_gains[i])} 倍',
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
  return StatefulBuilder(
    builder: (context, setState) {
      var expanded = _SubtitleSection.primary;

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
          _PanelRow(
            title: '字幕搜索',
            onTap: onSearch,
          ),
          _PanelRow(
            title: '本地导入',
            onTap: onImport,
          ),
          _PanelRow(
            title: '字幕设置',
            onTap: onSettings,
          ),
          _PanelRow(
            title: '永久禁用',
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 11, 14, 11),
          child: Row(
            children: [
              Icon(
                open
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_right_rounded,
                size: 18,
                color: _inkSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: _ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
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
    return Material(
      color: checked ? const Color(0x14385480) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 0, 14, 0),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: checked
                      ? Icon(Icons.check_rounded, size: 16, color: _ink)
                      : null,
                ),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _ink,
                      fontSize: 14.5,
                      fontWeight:
                          checked ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
        value: '${settings.delay >= 0 ? '+' : ''}${settings.delay.toStringAsFixed(1)}s',
        onMinus: () => onChanged(settings.copyWith(
            delay: (settings.delay - 0.5).clamp(-10, 10))),
        onPlus: () => onChanged(
            settings.copyWith(delay: (settings.delay + 0.5).clamp(-10, 10))),
      ),
      _StepperRow(
        label: '垂直偏移',
        value: '${settings.verticalOffset.round()}',
        onMinus: () => onChanged(settings.copyWith(
            verticalOffset: (settings.verticalOffset - 5).clamp(0, 100))),
        onPlus: () => onChanged(settings.copyWith(
            verticalOffset: (settings.verticalOffset + 5).clamp(0, 100))),
      ),
      _StepperRow(
        label: '大小缩放',
        value: '${settings.scale.toStringAsFixed(2)}×',
        onMinus: () => onChanged(
            settings.copyWith(scale: (settings.scale - 0.1).clamp(0.5, 2))),
        onPlus: () => onChanged(
            settings.copyWith(scale: (settings.scale + 0.1).clamp(0.5, 2))),
      ),
      _StepperRow(
        label: '不透明度',
        value: '${(settings.opacity * 100).round()}%',
        onMinus: () => onChanged(settings.copyWith(
            opacity: (settings.opacity - 0.1).clamp(0.1, 1))),
        onPlus: () => onChanged(
            settings.copyWith(opacity: (settings.opacity + 0.1).clamp(0.1, 1))),
      ),
      if (onReset != null) ...[
        Container(
          height: 0.8,
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          color: _ink.withValues(alpha: 0.08),
        ),
        _PanelRow(title: '重置为默认', onTap: onReset),
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
  required VoidCallback onMarkOutro,
  required ValueChanged<bool> onIntroChanged,
  required ValueChanged<bool> onOutroChanged,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _PanelRow(
        icon: Icons.bookmark_outline_rounded,
        title: '标记当前进度为片尾',
        onTap: onMarkOutro,
      ),
      _PanelRow(
        icon: Icons.skip_next_rounded,
        title: '自动跳过片头',
        subtitle: introSkip ? '已开启' : '关闭',
        onTap: () => onIntroChanged(!introSkip),
      ),
      _PanelRow(
        icon: Icons.skip_next_rounded,
        title: '自动跳过片尾',
        subtitle: outroSkip ? '已开启' : '关闭',
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
  final index = _sleepOptions.indexOf(current).clamp(0, _sleepOptions.length - 1);
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
          selected: current >= c.start &&
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
                  style: TextStyle(
                    color: _ink,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
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
