import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/pages/emby/emby_lu_play.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/request/clients/download_http_client.dart';
import 'package:XL/services/emby/lu_media_vault.dart';
import 'package:XL/services/url_parse/url_parse_service.dart';
import 'package:XL/theme/ios_interaction.dart';

/// 资源库「网络链接」入口页。
///
/// 对应参考稿的 URL 页：一个「打开 URL 链接」、一个「下载」。两者共用同一
/// 张输入面板，面板打开时会尝试把剪贴板里的网址直接填进去，省掉手动长按
/// 粘贴这一步。播放仍走原来的解析接口 + LU 播放器；下载把文件落到应用
/// 私有目录并登记到「本地文件」，离线可播。
class EmbyUrlPage extends StatefulWidget {
  const EmbyUrlPage({super.key});

  @override
  State<EmbyUrlPage> createState() => _EmbyUrlPageState();
}

class _EmbyUrlPageState extends State<EmbyUrlPage> {
  bool _downloading = false;
  double _progress = 0;
  String _downloadName = '';

  Future<void> _openInput({required bool download}) async {
    final result = await showModalBottomSheet<({String url, String ua})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: PvColors.card(context),
      builder: (_) => _UrlInputSheet(download: download),
    );
    if (result == null || !mounted) return;
    final url = result.url.trim();
    if (url.isEmpty) return;
    if (download) {
      await _download(url, result.ua.trim());
    } else {
      await _play(url);
    }
  }

  Future<void> _play(String rawUrl) async {
    String playUrl = rawUrl;
    if (UrlParseService.enabled) {
      try {
        playUrl = await UrlParseService.resolve(rawUrl);
      } on UrlParseException catch (e) {
        if (!mounted) return;
        KazumiDialog.showError(message: e.message, context: context);
        return;
      } catch (e) {
        if (!mounted) return;
        KazumiDialog.showError(
          message: '解析失败：${e.toString().split('\n').first}',
          context: context,
        );
        return;
      }
    }
    if (!mounted) return;
    final name = Uri.tryParse(playUrl)?.pathSegments.lastOrNull ?? '网络视频';
    await LuMediaVault.instance.addEntries('link', [
      (name: name, source: playUrl),
    ]);
    if (!mounted) return;
    // 播放器参数里没有 UA 位；自定义 UA 只对下载请求生效。
    luPlay(context, title: name, url: playUrl);
  }

  Future<void> _download(String rawUrl, String ua) async {
    String url = rawUrl;
    if (UrlParseService.enabled) {
      try {
        url = await UrlParseService.resolve(rawUrl);
      } on UrlParseException catch (e) {
        if (!mounted) return;
        KazumiDialog.showError(message: e.message, context: context);
        return;
      } catch (e) {
        if (!mounted) return;
        KazumiDialog.showError(
          message: '解析失败：${e.toString().split('\n').first}',
          context: context,
        );
        return;
      }
    }

    var name = 'video';
    try {
      final last = Uri.parse(url).pathSegments.lastOrNull;
      if (last != null && last.isNotEmpty) name = Uri.decodeComponent(last);
    } catch (_) {}
    if (!name.contains('.')) name = '$name.mp4';
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    if (!mounted) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _downloadName = safe;
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      final target = Directory('${dir.path}/vault/local');
      if (!await target.exists()) {
        await target.create(recursive: true);
      }
      final savePath =
          '${target.path}/${DateTime.now().millisecondsSinceEpoch}_$safe';
      await DownloadHttpClient.instance.download(
        url,
        savePath,
        headers: ua.isEmpty ? const <String, dynamic>{} : {'User-Agent': ua},
        onReceiveProgress: (received, total) {
          if (!mounted) return;
          setState(() => _progress = total > 0 ? received / total : -1);
        },
      );
      await LuMediaVault.instance.addEntries('local', [
        (name: safe, source: savePath),
      ]);
      if (!mounted) return;
      KazumiDialog.showToast(message: '已下载到「本地文件」', context: context);
    } catch (e) {
      if (!mounted) return;
      KazumiDialog.showError(
        message: '下载失败：${e.toString().split('\n').first}',
        context: context,
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _progress = 0;
          _downloadName = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PvColors.page(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leading: const KzBackButton(),
        title: const Text('URL'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Icon(Icons.laptop_mac_rounded, size: 82, color: PvColors.blue),
                const SizedBox(height: 36),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () => _openInput(download: false),
                    icon: const Icon(Icons.link_rounded, size: 18),
                    label: const Text('打开 URL 链接'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _downloading
                        ? null
                        : () => _openInput(download: true),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('下载'),
                  ),
                ),
                if (_downloading) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: PvColors.card(context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '正在下载 $_downloadName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PvText.rowSub(context),
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: _progress < 0 ? null : _progress.clamp(0, 1),
                          minHeight: 4,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _progress < 0
                              ? '已接收数据，服务器未返回总大小'
                              : '${(_progress * 100).round()}%',
                          style: PvText.count(context),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// URL 输入面板：打开时读一次剪贴板，看起来像网址就直接填上。
class _UrlInputSheet extends StatefulWidget {
  const _UrlInputSheet({required this.download});

  final bool download;

  @override
  State<_UrlInputSheet> createState() => _UrlInputSheetState();
}

class _UrlInputSheetState extends State<_UrlInputSheet> {
  final _url = TextEditingController();
  final _ua = TextEditingController();
  bool _autoPasted = false;

  @override
  void initState() {
    super.initState();
    _pasteFromClipboard(auto: true);
  }

  @override
  void dispose() {
    _url.dispose();
    _ua.dispose();
    super.dispose();
  }

  static bool _looksLikeUrl(String text) {
    final uri = Uri.tryParse(text);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    return const {
      'http',
      'https',
      'm3u8',
      'rtmp',
      'rtmps',
      'magnet',
    }.contains(scheme);
  }

  Future<void> _pasteFromClipboard({bool auto = false}) async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty || !_looksLikeUrl(text)) return;
      if (!mounted || _url.text.trim().isNotEmpty) return;
      setState(() {
        _url.text = text;
        _autoPasted = true;
      });
    } catch (_) {
      // 剪贴板被系统限制时静默：用户仍可手动输入。
    }
  }

  void _done() {
    final url = _url.text.trim();
    if (url.isEmpty) {
      KazumiDialog.showToast(message: '请先填写 URL', context: context);
      return;
    }
    Navigator.of(context).pop((url: url, ua: _ua.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      widget.download ? '下载 URL 链接' : '打开 URL 链接',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(onPressed: _done, child: const Text('完成')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                decoration: BoxDecoration(
                  color: PvColors.glassRow(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 14),
                        SizedBox(
                          width: 78,
                          child: Text('URL', style: PvText.rowTitle(context)),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _url,
                            autofocus: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              hintText: '必填',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '从剪贴板粘贴',
                          icon: const Icon(
                            Icons.content_paste_rounded,
                            size: 20,
                          ),
                          onPressed: () => _pasteFromClipboard(),
                        ),
                      ],
                    ),
                    Divider(
                      height: 1,
                      indent: 14,
                      color: PvColors.hair(context),
                    ),
                    Row(
                      children: [
                        const SizedBox(width: 14),
                        SizedBox(
                          width: 78,
                          child: Text(
                            'User-Agent',
                            style: PvText.rowTitle(context),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _ua,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: const InputDecoration(
                              hintText: '可选，仅下载时生效',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_autoPasted)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('已自动粘贴剪贴板中的链接', style: PvText.count(context)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
