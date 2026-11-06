import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/services/emby/lu_media_vault.dart';

/// 扫一扫得到的东西。
class EmbyScanResult {
  const EmbyScanResult({required this.type, required this.server});

  /// `emby` / `jellyfin` / `webdav` / `ftp` / `smb`。
  final String type;

  /// 预填值（id 为空，只用来填表单）。
  final LuVaultServer server;
}

/// 扫二维码添加服务器。
///
/// 解析三种常见形态，其它一律判为「不认识」：
///
/// 1. **JSON**（我们自己分享出去的格式）：
///    `{"type":"emby","host":"1.2.3.4","port":8096,"user":"a","password":"b"}`
/// 2. **URL**：`https://host:8096` —— 主机、端口、https 直接拆出来
/// 3. **`luserver://` 自定义 scheme**：`luserver://emby?host=..&port=..`
///
/// 不做「扫到什么都当地址」的猜测：会场二维码、付款码都是二维码，
/// 猜错的代价是把一串乱码填进主机框，用户还得自己删。
class EmbyScanPage extends StatefulWidget {
  const EmbyScanPage({super.key});

  @override
  State<EmbyScanPage> createState() => _EmbyScanPageState();
}

class _EmbyScanPageState extends State<EmbyScanPage> {
  late final MobileScannerController _controller;
  bool _handled = false;
  bool _torch = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
      autoStart: true,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) {
      return;
    }
    for (final Barcode code in capture.barcodes) {
      final String? raw = code.rawValue;
      if (raw == null || raw.trim().isEmpty) {
        continue;
      }
      final EmbyScanResult? parsed = parseScanPayload(raw);
      if (parsed == null) {
        // 认出来是二维码、但不是服务器配置：给一次提示，然后继续扫。
        KazumiDialog.showError(message: '这不是服务器二维码');
        return;
      }
      _handled = true;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(parsed);
      return;
    }
  }

  Future<void> _pickFromGallery() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (file == null || !mounted) {
      return;
    }
    try {
      final BarcodeCapture? capture = await _controller.analyzeImage(file.path);
      if (capture == null || !mounted) {
        KazumiDialog.showError(message: '图片里没有识别到二维码');
        return;
      }
      for (final Barcode code in capture.barcodes) {
        final String? raw = code.rawValue;
        if (raw == null) {
          continue;
        }
        final EmbyScanResult? parsed = parseScanPayload(raw);
        if (parsed != null) {
          Navigator.of(context).pop(parsed);
          return;
        }
      }
      KazumiDialog.showError(message: '这不是服务器二维码');
    } catch (e) {
      KazumiDialog.showError(message: '读取图片失败');
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      if (mounted) {
        setState(() => _torch = !_torch);
      }
    } catch (_) {
      KazumiDialog.showError(message: '这台设备没有可用的闪光灯');
    }
  }

  @override
  Widget build(BuildContext context) {
    final double side = MediaQuery.sizeOf(context).shortestSide;
    final double box = (side * 0.68).clamp(210.0, 300.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              _error = '相机不可用：${error.errorCode.name}';
              return const ColoredBox(color: Colors.black);
            },
          ),
          // 遮罩 + 取景框四角
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _ScannerOverlay(box: box)),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: const Alignment(0, -0.34),
                child: SizedBox(
                  width: box,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const SizedBox(height: 26),
                      const Text(
                        '扫码添加',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error ?? '把服务器二维码放进框内，会自动识别',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.66),
                          fontSize: 13,
                          height: 1.4,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: MediaQuery.paddingOf(context).top + 8,
            child: _RoundIcon(
              icon: Icons.close_rounded,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.paddingOf(context).bottom + 54,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _ToolButton(
                  icon: _torch
                      ? Icons.flashlight_on_rounded
                      : Icons.flashlight_off_rounded,
                  label: '手电筒',
                  active: _torch,
                  onTap: _toggleTorch,
                ),
                const SizedBox(width: 56),
                _ToolButton(
                  icon: Icons.photo_library_outlined,
                  label: '相册',
                  onTap: _pickFromGallery,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 半透明遮罩 + 取景框四角。
///
/// 用 `Path.combine(difference)` 挖洞，而不是拿四条半透明边拼一个框：
/// 拼出来的框在圆角处接不严，会露出亮边。
class _ScannerOverlay extends CustomPainter {
  const _ScannerOverlay({required this.box});

  final double box;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect hole = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: box,
      height: box,
    );
    final RRect holeRRect = RRect.fromRectAndRadius(
      hole,
      const Radius.circular(20),
    );

    final Path mask = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(holeRRect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, mask, Path()..addRRect(holeRRect)),
      Paint()..color = Colors.black.withValues(alpha: 0.46),
    );

    // 四角
    const double len = 30;
    final Paint corner = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final double l = hole.left;
    final double t = hole.top;
    final double r = hole.right;
    final double b = hole.bottom;

    final Path path = Path()
      ..moveTo(l, t + len)
      ..lineTo(l, t + 20)
      ..arcToPoint(Offset(l + 20, t), radius: const Radius.circular(20))
      ..lineTo(l + len + 10, t)
      ..moveTo(r - len - 10, t)
      ..lineTo(r - 20, t)
      ..arcToPoint(Offset(r, t + 20), radius: const Radius.circular(20))
      ..lineTo(r, t + len)
      ..moveTo(r, b - len)
      ..lineTo(r, b - 20)
      ..arcToPoint(Offset(r - 20, b), radius: const Radius.circular(20))
      ..lineTo(r - len - 10, b)
      ..moveTo(l + len + 10, b)
      ..lineTo(l + 20, b)
      ..arcToPoint(Offset(l, b - 20), radius: const Radius.circular(20))
      ..lineTo(l, b - len);

    canvas.drawPath(path, corner);
  }

  @override
  bool shouldRepaint(_ScannerOverlay old) => old.box != box;
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.16),
        ),
        child: Icon(icon, size: 19, color: Colors.white),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? Colors.white.withValues(alpha: 0.86)
                  : Colors.white.withValues(alpha: 0.14),
            ),
            child: Icon(
              icon,
              size: 22,
              color: active ? Colors.black : Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

/// 解析二维码内容。认不出来返回 null（调用方负责提示）。
EmbyScanResult? parseScanPayload(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) {
    return null;
  }

  // ---- 1. JSON ----
  if (text.startsWith('{')) {
    try {
      final Map<String, dynamic> m = jsonDecode(text) as Map<String, dynamic>;
      final String host = (m['host'] ?? m['server'] ?? m['address'] ?? '')
          .toString()
          .trim();
      if (host.isNotEmpty) {
        return EmbyScanResult(
          type: _normalizeType(m['type']?.toString()),
          server: LuVaultServer(
            id: '',
            type: _normalizeType(m['type']?.toString()),
            name: (m['name'] ?? '').toString(),
            host: host,
            port: _asInt(m['port']),
            user: (m['user'] ?? m['username'] ?? '').toString(),
            password: (m['password'] ?? m['pass'] ?? '').toString(),
            https: m['https'] == true,
          ),
        );
      }
    } catch (_) {
      // 不是 JSON，往下走 URL 分支。
    }
  }

  // ---- 2. luserver:// ----
  final Uri? custom = Uri.tryParse(text);
  if (custom != null && custom.scheme == 'luserver') {
    final String host = custom.host.isNotEmpty
        ? custom.host
        : (custom.queryParameters['host'] ?? '');
    if (host.isNotEmpty) {
      final String type = _normalizeType(
        custom.queryParameters['type'] ??
            (custom.path.isNotEmpty ? custom.path.replaceAll('/', '') : 'emby'),
      );
      return EmbyScanResult(
        type: type,
        server: LuVaultServer(
          id: '',
          type: type,
          name: custom.queryParameters['name'] ?? '',
          host: host,
          port: _asInt(custom.queryParameters['port']),
          user: custom.queryParameters['user'] ?? '',
          password: custom.queryParameters['password'] ?? '',
          https: custom.queryParameters['https'] == '1',
        ),
      );
    }
  }

  // ---- 3. http(s):// ----
  if (custom != null &&
      (custom.scheme == 'http' || custom.scheme == 'https') &&
      custom.host.isNotEmpty) {
    return EmbyScanResult(
      type: 'emby',
      server: LuVaultServer(
        id: '',
        type: 'emby',
        host: custom.host,
        port: custom.hasPort ? custom.port : 0,
        path: custom.path == '/' ? '' : custom.path,
        https: custom.scheme == 'https',
      ),
    );
  }

  return null;
}

String _normalizeType(String? raw) {
  final String t = (raw ?? '').toLowerCase().trim();
  switch (t) {
    case 'jellyfin':
      return 'jellyfin';
    case 'webdav':
      return 'webdav';
    case 'ftp':
      return 'ftp';
    case 'smb':
      return 'smb';
    default:
      return 'emby';
  }
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse('${value ?? ''}') ?? 0;
}
