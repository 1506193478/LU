import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/emby/player/emby_player_controller.dart';
import 'package:XL/services/emby/emby_stream_prefs.dart';

/// 字幕搜索页（对标 iOS 播放器的字幕搜索）。
///
/// 不做在菜单卡片里——搜索要打字、要滚结果列表，卡片里塞不下。整页深色，
/// 从播放器菜单「字幕搜索」整页推入，搜索框预填「剧名 SxxExx」：
///
///   * 输入框可以改（手动优化名称可提高匹配精度）；
///   * 下方 chips 是这一集的其它候选名（集名 / 剧名），点一下就填进输入框；
///   * 右上「搜索」按 SearchInfo（剧名 + 季 + 集，或纯片名）发模糊查询，
///     关键词和关联结果都会回来；
///   * 点结果 → 下载到服务器并立刻挂上。
Future<void> showEmbySubtitleSearchPage(
  BuildContext context, {
  required EmbyPlayerController controller,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, a2, a3) =>
          EmbySubtitleSearchPage(controller: controller),
      transitionsBuilder: (_, anim, a4, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeIn,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

class EmbySubtitleSearchPage extends StatefulWidget {
  const EmbySubtitleSearchPage({super.key, required this.controller});

  final EmbyPlayerController controller;

  @override
  State<EmbySubtitleSearchPage> createState() => _EmbySubtitleSearchPageState();
}

class _EmbySubtitleSearchPageState extends State<EmbySubtitleSearchPage> {
  late final TextEditingController _query = TextEditingController(
    text: _defaultQuery(),
  );
  List<EmbyRemoteSubtitle> _results = const [];
  String _error = '';
  bool _searching = false;
  bool _applying = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  String _defaultQuery() {
    final item = widget.controller.current;
    final series = item?.seriesName?.trim() ?? '';
    final label = widget.controller.episodeLabel.trim();
    if (series.isNotEmpty && label.isNotEmpty) return '$series $label';
    if (series.isNotEmpty) return series;
    return widget.controller.launch.title;
  }

  List<String> get _candidates {
    final item = widget.controller.current;
    final out = <String>[];
    for (final name in [item?.name, item?.seriesName]) {
      final value = name?.trim() ?? '';
      if (value.isEmpty) continue;
      if (value == _query.text.trim()) continue;
      if (out.contains(value)) continue;
      out.add(value);
    }
    return out;
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty || _searching) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = '';
      _results = const [];
    });
    try {
      // 「剧名 S01E06」这种格式拆成剧名+季+集，命中率远高于整串丢给服务端；
      // 拆不出来就当片名搜。
      final m = RegExp(
        r'^(.*?)\s*[Ss](\d{1,2})\s*[Ee×xX](\d{1,3})\b',
      ).firstMatch(query);
      final found = await widget.controller.searchRemoteSubtitlesByQuery(
        language: EmbyStreamPrefs.subtitleLanguage.isEmpty
            ? 'chi'
            : EmbyStreamPrefs.subtitleLanguage,
        seriesName: m?.group(1),
        season: m == null ? null : int.tryParse(m.group(2)!),
        episode: m == null ? null : int.tryParse(m.group(3)!),
        name: m == null ? query : null,
      );
      if (!mounted) return;
      setState(() {
        _results = found;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error =
            '搜索失败：$e\n\n'
            '字幕搜索用的是服务器上的字幕插件，需要到 Emby 后台装好 '
            'OpenSubtitles 插件并配好账号。';
      });
    }
  }

  Future<void> _apply(EmbyRemoteSubtitle sub) async {
    if (_applying) return;
    setState(() => _applying = true);
    HapticFeedback.selectionClick();
    final ok = await widget.controller.applyRemoteSubtitle(sub);
    if (!mounted) return;
    setState(() => _applying = false);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(ok ? '字幕已挂上' : '这条字幕没能下载'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (ok && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0F),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildQueryCard(),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        '手动优化名称可提高字幕匹配精度',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildBody(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded, size: 24),
            color: Colors.white,
          ),
          const Expanded(
            child: Text(
              '字幕搜索',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: _searching ? null : _search,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: _searching
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  )
                : const Text(
                    '搜索',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueryCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _query,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w500,
                  ),
                  cursorColor: Colors.white70,
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                    hintText: '剧名 / 片名',
                    hintStyle: TextStyle(color: Colors.white24),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              if (_query.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    setState(() => _query.clear());
                  },
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Color(0xFF48484A),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: Colors.black87,
                    ),
                  ),
                ),
            ],
          ),
          if (_candidates.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final name in _candidates)
                        GestureDetector(
                          onTap: () {
                            setState(() => _query.text = name);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              name,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _query.clear());
                  },
                  child: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
        child: Text(
          _error,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 13,
            height: 1.5,
          ),
        ),
      );
    }
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(child: CircularProgressIndicator(color: Colors.white70)),
      );
    }
    if (_results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(
          child: Text(
            _query.text.isEmpty ? '输入名称后点右上角搜索' : '没有找到可用的字幕',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 13.5,
            ),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (int i = 0; i < _results.length; i++) ...[
            if (i > 0)
              Divider(
                height: 0.5,
                thickness: 0.5,
                indent: 16,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            _ResultRow(
              subtitle: _results[i],
              busy: _applying,
              onTap: () => _apply(_results[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.subtitle,
    required this.onTap,
    this.busy = false,
  });

  final EmbyRemoteSubtitle subtitle;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (subtitle.language.isNotEmpty) subtitleLanguageName(subtitle.language),
      if (subtitle.format.isNotEmpty) subtitle.format.toUpperCase(),
      if (subtitle.isHashMatch) '匹配片源',
    ];
    return InkWell(
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subtitle.name.isEmpty ? '未命名字幕' : subtitle.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final m in meta)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Text(
                              m,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                Icons.download_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.35),
              ),
          ],
        ),
      ),
    );
  }
}

/// 三字码转中文名（页面里只展示用，取常用语言就够）。
String subtitleLanguageName(String code) {
  final key = code.toLowerCase().split(RegExp(r'[-,;]')).first.trim();
  return switch (key) {
    'zh' || 'chi' || 'zho' => '简体中文',
    'zh-tw' || 'zh-hk' || 'zht' => '繁体中文',
    'ja' || 'jpn' => '日语',
    'en' || 'eng' => '英语',
    'ko' || 'kor' => '韩语',
    'fr' || 'fra' => '法语',
    'de' || 'deu' => '德语',
    'es' || 'spa' => '西班牙语',
    'ru' || 'rus' => '俄语',
    'pt' || 'por' => '葡萄牙语',
    'th' || 'tha' => '泰语',
    'fa' || 'per' || 'fas' => '波斯语',
    'it' || 'ita' => '意大利语',
    'und' || '' => '未知语言',
    _ => code,
  };
}
