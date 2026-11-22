import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/services/network/wifi_transfer_service.dart';

/// 「我的 → Wi-Fi 传文件」：局域网浏览器上传入口。
class WifiTransferPage extends StatefulWidget {
  const WifiTransferPage({super.key});

  @override
  State<WifiTransferPage> createState() => _WifiTransferPageState();
}

class _WifiTransferPageState extends State<WifiTransferPage> {
  final WifiTransferService _service = WifiTransferService.instance;
  String? _address;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _address = _service.address;
  }

  @override
  void dispose() {
    // 页面退出就关服务，避免一直占着端口。
    if (_service.isRunning) _service.stop();
    super.dispose();
  }

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      if (_service.isRunning) {
        await _service.stop();
        if (mounted) setState(() => _address = null);
      } else {
        final address = await _service.start();
        if (mounted) setState(() => _address = address);
      }
    } catch (e) {
      if (mounted) KazumiDialog.showToast(message: '启动失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    if (_address == null) return;
    await Clipboard.setData(ClipboardData(text: _address!));
    if (mounted) KazumiDialog.showToast(message: '地址已复制');
  }

  @override
  Widget build(BuildContext context) {
    final dark = PvColors.isDark(context);
    final running = _service.isRunning;
    return Scaffold(
      backgroundColor: PvColors.glassRow(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Wi-Fi 传文件',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          PvGroup(
            children: [
              PvRow(
                icon: Icons.wifi_tethering_rounded,
                iconColor: const Color(0xFF34C759),
                title: '开启传输服务',
                subtitle: '同一 Wi-Fi 下的设备用浏览器访问',
                value: running ? '运行中' : '已停止',
                trailingWidget: PvSwitch(
                  value: running,
                  onChanged: (_) {
                    if (!_busy) _toggle();
                  },
                ),
                trailing: PvRowTrailing.widget,
                showDivider: _address != null,
              ),
              if (_address != null)
                PvRow(
                  icon: Icons.link_rounded,
                  iconColor: const Color(0xFF0A84FF),
                  title: '访问地址',
                  subtitle: _address,
                  onTap: _copy,
                  showDivider: false,
                ),
            ],
          ),
          if (_address != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: dark ? Colors.white.withValues(alpha: .06) : Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '1. 手机 / 电脑连上同一个 Wi-Fi\n'
                '2. 浏览器打开上面的地址\n'
                '3. 选择文件（可多选）并点「上传」\n'
                '4. 文件保存在应用的「下载目录 / WiFi传输」\n\n'
                '关闭本页面会自动停止服务。上传的文件不会进入番剧下载库。',
                style: PvText.rowSub(context).copyWith(height: 1.7),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '提示：iOS 上浏览器与 App 需在同一局域网；部分路由器开启了「AP 隔离」，'
              '会导致设备之间互相访问不了，此时请关闭该选项。',
              style: PvText.rowSub(context).copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
