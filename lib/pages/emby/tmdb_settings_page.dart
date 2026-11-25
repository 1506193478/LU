import 'package:flutter/material.dart';

import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/request/clients/tmdb_client.dart';
import 'package:XL/services/emby/tmdb_prefs.dart';

/// 「我的 → TMDB 配置」：客户端直连 TMDB 的设置页。
///
/// 零配置可用：内置公共 v3 Key 兜底 + 候选线路一键探测选线。
/// 高级用户可覆盖：自己的 API Key、自定义 API 地址、图片地址。
/// 配置后「识别元数据」面板会多一个「TMDB 直连」数据源。
enum _LineState { pending, testing, ok, failed }

class TmdbSettingsPage extends StatefulWidget {
  const TmdbSettingsPage({super.key});

  @override
  State<TmdbSettingsPage> createState() => _TmdbSettingsPageState();
}

class _TmdbSettingsPageState extends State<TmdbSettingsPage> {
  late final TextEditingController _key;
  late final TextEditingController _api;
  late final TextEditingController _image;
  String? _testError;
  bool _tested = false;
  bool _testing = false;

  List<_LineState> _lineStatus =
      List<_LineState>.filled(TmdbPrefs.builtinLines.length, _LineState.pending);
  bool _probing = false;
  String? _probeMsg;

  @override
  void initState() {
    super.initState();
    _key = TextEditingController(text: TmdbPrefs.apiKey);
    _api = TextEditingController(text: TmdbPrefs.customBase);
    _image = TextEditingController(text: TmdbPrefs.imageBase);
  }

  @override
  void dispose() {
    _key.dispose();
    _api.dispose();
    _image.dispose();
    super.dispose();
  }

  /// 把输入框里的值写进存储。API 地址留空 = 清除自定义（自动选线接管）。
  Future<void> _saveFields() async {
    await TmdbPrefs.setApiKey(_key.text);
    await TmdbPrefs.setApiBase(
      _api.text.trim().isEmpty ? TmdbPrefs.defaultApiBase : _api.text,
    );
    await TmdbPrefs.setImageBase(
      _image.text.trim().isEmpty ? TmdbPrefs.defaultImageBase : _image.text,
    );
  }

  Future<void> _saveAndTest() async {
    await _saveFields();
    setState(() {
      _testing = true;
      _tested = false;
      _testError = null;
    });
    final error = await TmdbClient().testConnection();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _tested = true;
      _testError = error;
    });
  }

  Future<void> _autoSelectLine() async {
    await _saveFields();
    setState(() {
      _probing = true;
      _probeMsg = null;
      _lineStatus = List<_LineState>.filled(
        TmdbPrefs.builtinLines.length,
        _LineState.pending,
      );
    });
    final found = await TmdbClient().probeLines(
      onProgress: (index, total) {
        if (mounted) {
          setState(() => _lineStatus[index] = _LineState.testing);
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _probing = false;
      if (found != null) {
        final winner =
            TmdbPrefs.builtinLines.indexWhere((l) => l.url == found);
        for (var i = 0; i < _lineStatus.length; i++) {
          _lineStatus[i] =
              i == winner ? _LineState.ok : _LineState.failed;
        }
        _probeMsg = '已选用：${TmdbPrefs.builtinLines[winner].label}';
      } else {
        for (var i = 0; i < _lineStatus.length; i++) {
          _lineStatus[i] = _LineState.failed;
        }
        _probeMsg = '全部线路不通：挂代理后重试，或在下方填自定义 API 地址';
      }
    });
  }

  Widget _field({
    required IconData icon,
    required String label,
    required String hint,
    required TextEditingController controller,
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: PvColors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              autocorrect: false,
              enableSuggestions: false,
              style: PvText.rowTitle(context),
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                labelStyle: PvText.rowSub(context),
                hintStyle: PvText.rowSub(context),
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (_) {
                if (_tested) setState(() => _tested = false);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineRow(int index) {
    final line = TmdbPrefs.builtinLines[index];
    final state = _lineStatus[index];
    final isCurrent = !TmdbPrefs.hasCustomBase && TmdbPrefs.apiBase == line.url;
    final (icon, color) = switch (state) {
      _LineState.pending => (
          isCurrent
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          isCurrent ? PvColors.green : PvColors.dockIdle,
        ),
      _LineState.testing => (
          Icons.timelapse_rounded,
          PvColors.blue,
        ),
      _LineState.ok => (Icons.check_circle_rounded, PvColors.green),
      _LineState.failed => (Icons.cancel_rounded, PvColors.red),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.label, style: PvText.rowTitle(context)),
                const SizedBox(height: 2),
                Text(line.url, style: PvText.rowSub(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'TMDB 配置',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 10, bottom: 40),
        children: [
          // 开箱即用说明。
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: PvColors.dockIdle),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    TmdbPrefs.usingBuiltinKey
                        ? '无需任何配置：已内置公共 API Key，线路可一键自动选择。想更稳可填自己的 Key（themoviedb.org 免费申请）。'
                        : '已使用你自己的 API Key。',
                    style: PvText.rowSub(context).copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          // 线路探测。
          PvGroup(
            children: [
              for (var i = 0; i < TmdbPrefs.builtinLines.length; i++)
                if (i > 0)
                  Column(
                    children: [
                      const Divider(height: 1, indent: 56),
                      _lineRow(i),
                    ],
                  )
                else
                  _lineRow(i),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 40,
              child: OutlinedButton.icon(
                onPressed: _probing ? null : _autoSelectLine,
                icon: _probing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.travel_explore_rounded, size: 17),
                label: Text(_probing ? '探测线路中…' : '自动选择线路'),
              ),
            ),
          ),
          if (_probeMsg != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(_probeMsg!, style: PvText.rowSub(context)),
            ),
          const SizedBox(height: 16),
          // 高级自定义（全部可留空）。
          PvGroup(
            children: [
              _field(
                icon: Icons.key_rounded,
                label: 'API Key 或读取令牌',
                hint: '留空使用内置公共 Key',
                controller: _key,
              ),
              const Divider(height: 1, indent: 56),
              _field(
                icon: Icons.link_rounded,
                label: 'API 地址',
                hint: '留空自动选择线路',
                controller: _api,
              ),
              const Divider(height: 1, indent: 56),
              _field(
                icon: Icons.image_rounded,
                label: '图片地址',
                hint: TmdbPrefs.defaultImageBase,
                controller: _image,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              '三项都可留空。令牌以 eyJ 开头会自动按 Bearer 方式发送；自定义 API 地址会覆盖自动选线。',
              style: PvText.rowSub(context).copyWith(height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 44,
              child: FilledButton.icon(
                onPressed: _testing ? null : _saveAndTest,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_find_rounded, size: 18),
                label: Text(_testing ? '测试中…' : '测试连接'),
              ),
            ),
          ),
          if (_tested)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: [
                  Icon(
                    _testError == null
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    size: 18,
                    color: _testError == null ? PvColors.green : PvColors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _testError ?? '连接正常',
                      style: PvText.rowSub(context).copyWith(
                        color: _testError == null ? PvColors.green : PvColors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
