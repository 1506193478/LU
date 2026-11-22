import 'package:flutter/material.dart';

import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/request/clients/tmdb_client.dart';
import 'package:XL/services/emby/tmdb_prefs.dart';

/// 「我的 → TMDB 配置」：客户端直连 TMDB 的自定义 API 设置。
///
/// 四个字段对齐 SenPlayer：API Key / 读取令牌、API 地址、图片地址、测试连接。
/// 配置后「识别元数据」面板会多一个「TMDB 直连」数据源。
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

  @override
  void initState() {
    super.initState();
    _key = TextEditingController(text: TmdbPrefs.apiKey);
    _api = TextEditingController(text: TmdbPrefs.apiBase);
    _image = TextEditingController(text: TmdbPrefs.imageBase);
  }

  @override
  void dispose() {
    _key.dispose();
    _api.dispose();
    _image.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    // 先存再测：测试用的就是当前输入框里的值。
    await TmdbPrefs.setApiKey(_key.text);
    await TmdbPrefs.setApiBase(
      _api.text.trim().isEmpty ? TmdbPrefs.defaultApiBase : _api.text,
    );
    await TmdbPrefs.setImageBase(
      _image.text.trim().isEmpty ? TmdbPrefs.defaultImageBase : _image.text,
    );
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
          PvGroup(
            children: [
              _field(
                icon: Icons.key_rounded,
                label: 'API Key 或读取令牌',
                hint: 'v3 Key 或以 eyJ 开头的 Bearer 令牌',
                controller: _key,
              ),
              const Divider(height: 1, indent: 56),
              _field(
                icon: Icons.link_rounded,
                label: 'API 地址',
                hint: TmdbPrefs.defaultApiBase,
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
              '留空则使用默认地址。留「API Key」空时，「识别元数据」仍可用服务端自带的元数据源。令牌以 eyJ 开头会自动按 Bearer 方式发送。',
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
