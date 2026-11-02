import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/pages/emby/emby_sheet_fields.dart';
import 'package:XL/services/emby/lu_media_vault.dart';

/// 服务器表单里「备用线路」那一行的落地页。
///
/// 主线路连不上时，[EmbyClient] 会按这里的顺序依次换上去，所以这页就是
/// 一条「地址队列」的编辑器：空的时候给「无内容」，点右上角「+」新增一条。
///
/// 增删**实时**通过 [onChanged] 回写给表单——不能等 pop 的返回值，因为用户
/// 很可能下滑直接把卡片关掉，那样改动就白做了。
Future<void> showBackupLinesSheet(
  BuildContext context, {
  required List<LuBackupLine> lines,
  required ValueChanged<List<LuBackupLine>> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.30),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.94,
      child: _BackupLinesSheet(initial: lines, onChanged: onChanged),
    ),
  );
}

class _BackupLinesSheet extends StatefulWidget {
  const _BackupLinesSheet({required this.initial, required this.onChanged});

  final List<LuBackupLine> initial;
  final ValueChanged<List<LuBackupLine>> onChanged;

  @override
  State<_BackupLinesSheet> createState() => _BackupLinesSheetState();
}

class _BackupLinesSheetState extends State<_BackupLinesSheet> {
  late List<LuBackupLine> _lines;

  @override
  void initState() {
    super.initState();
    _lines = List<LuBackupLine>.of(widget.initial);
  }

  void _apply(List<LuBackupLine> next) {
    setState(() => _lines = next);
    widget.onChanged(next);
  }

  Future<void> _add() async {
    final result = await showBackupLineSheet(context);
    if (result == null || !result.saved || !mounted) return;
    _apply([..._lines, result.line!]);
  }

  Future<void> _edit(int index) async {
    final result = await showBackupLineSheet(context, existing: _lines[index]);
    if (result == null || !mounted) return;
    _apply(
      result.deleted
          ? ([..._lines]..removeAt(index))
          : ([..._lines]..[index] = result.line!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = PvColors.isDark(context);

    return Material(
      color: PvColors.page(context),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // 顶栏照设计稿：标题居中，右侧「‹」返回 + 「+」新增。
          // 这里没用 SheetTopBar——它的右槽是给「保存」的固定 76 宽，
          // 塞两颗按钮会挤到标题。用 Stack 保证标题严格居中。
          SizedBox(
            height: 52,
            child: Stack(
              children: [
                Center(
                  child: Text(
                    '备用线路',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: PvColors.ink(context),
                    ),
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 0,
                  bottom: 0,
                  child: Row(
                    children: [
                      _BarIcon(
                        icon: Icons.arrow_back_ios_new_rounded,
                        size: 19,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      _BarIcon(
                        icon: Icons.add_rounded,
                        size: 24,
                        onTap: _add,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _lines.isEmpty
                ? _NoContent(dark: dark)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 34),
                    children: [
                      for (var i = 0; i < _lines.length; i++)
                        _LineTile(
                          dark: dark,
                          line: _lines[i],
                          index: i,
                          onTap: () => _edit(i),
                          onDelete: () => _apply([..._lines]..removeAt(i)),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// 顶栏上的纯图标按钮。
///
/// 不能用 IconButton：它自带 48×48 的最小点击区，两颗并排就把标题挤偏了。
class _BarIcon extends StatelessWidget {
  const _BarIcon({
    required this.icon,
    required this.size,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 52,
        child: Icon(icon, size: size, color: const Color(0xFF007AFF)),
      ),
    );
  }
}

/// 一条线路：名字 + 拼好的地址，左滑删除。
class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.dark,
    required this.line,
    required this.index,
    required this.onTap,
    required this.onDelete,
  });

  final bool dark;
  final LuBackupLine line;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1F1E22) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
          child: Row(
            children: [
              // 序号就是切换顺序，写出来比让用户猜强。
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF007AFF),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        color: PvColors.ink(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      line.baseUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: dark
                            ? Colors.white.withValues(alpha: 0.4)
                            : const Color(0xFF8A8A8E),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: dark ? Colors.white24 : const Color(0xFFC7C7CC),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );

    return Dismissible(
      key: ValueKey<String>('line-${line.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.only(right: 18),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: const Color(0xFFE5484D),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          '删除',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      child: card,
    );
  }
}

/// 「无内容」空状态：空心圆环 + 斜杠。
class _NoContent extends StatelessWidget {
  const _NoContent({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final color = dark
        ? Colors.white.withValues(alpha: 0.38)
        : const Color(0xFF9A9AA0);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 3.5),
            ),
            child: Center(
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: 48,
                  height: 3.5,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '无内容',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: PvColors.ink(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「线路」编辑页的结果：保存了一条，或者删掉了这条。
class LineSheetResult {
  const LineSheetResult.saved(LuBackupLine this.line) : deleted = false;
  const LineSheetResult.deleted()
      : line = null,
        deleted = true;

  final LuBackupLine? line;
  final bool deleted;

  bool get saved => !deleted && line != null;
}

/// 单条线路的编辑页（设计稿里的「线路」）。
///
/// 只有地址四件套 + 名字，没有账号密码——登录态是跟着服务器走的。
Future<LineSheetResult?> showBackupLineSheet(
  BuildContext context, {
  LuBackupLine? existing,
}) {
  return showModalBottomSheet<LineSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.30),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.94,
      child: _LineSheet(existing: existing),
    ),
  );
}

class _LineSheet extends StatefulWidget {
  const _LineSheet({this.existing});

  final LuBackupLine? existing;

  @override
  State<_LineSheet> createState() => _LineSheetState();
}

class _LineSheetState extends State<_LineSheet> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _path;
  late final TextEditingController _port;
  bool _https = false;
  bool _failed = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _host = TextEditingController(text: e?.host ?? '');
    _path = TextEditingController(text: e?.path ?? '');
    _port = TextEditingController(text: (e?.port ?? 0) > 0 ? '${e!.port}' : '');
    _https = e?.https ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _path.dispose();
    _port.dispose();
    super.dispose();
  }

  void _save() {
    FocusScope.of(context).unfocus();
    if (_name.text.trim().isEmpty) {
      setState(() {
        _failed = true;
        _message = '给这条线路起个名字，方便以后分辨';
      });
      return;
    }
    if (_host.text.trim().isEmpty) {
      setState(() {
        _failed = true;
        _message = '请先填主机地址';
      });
      return;
    }
    // 端口留空时按协议给默认值：https 走 443，http 走 Emby 的 8096。
    final typed = int.tryParse(_port.text.trim()) ?? 0;
    final port = typed > 0 ? typed : (_https ? 443 : 8096);
    Navigator.of(context).pop(
      LineSheetResult.saved(
        LuBackupLine(
          id: widget.existing?.id ??
              'line-${DateTime.now().microsecondsSinceEpoch}',
          name: _name.text.trim(),
          host: _host.text.trim(),
          path: _path.text.trim(),
          port: port,
          https: _https,
        ),
      ),
    );
  }

  void _delete() {
    if (widget.existing == null) return;
    Navigator.of(context).pop(const LineSheetResult.deleted());
  }

  @override
  Widget build(BuildContext context) {
    final dark = PvColors.isDark(context);

    return Material(
      color: PvColors.page(context),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SheetTopBar(
            title: '线路',
            onClose: () => Navigator.of(context).maybePop(),
            onSave: _save,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 34),
              children: [
                SheetGroup(dark: dark, children: [
                  SheetFieldRow(
                    dark: dark,
                    label: '名称',
                    hint: 'Name (必填)',
                    controller: _name,
                  ),
                ]),
                SheetGroupLabel(dark: dark, text: '服务器地址'),
                SheetGroup(dark: dark, children: [
                  SheetFieldRow(
                    dark: dark,
                    label: '主机',
                    hint: 'Host (必填)',
                    controller: _host,
                  ),
                  SheetFieldRow(
                    dark: dark,
                    label: '路径',
                    hint: 'Path (可选)',
                    controller: _path,
                  ),
                  SheetFieldRow(
                    dark: dark,
                    label: '端口',
                    hint: '8096',
                    controller: _port,
                    keyboard: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  SheetSwitchRow(
                    dark: dark,
                    label: 'https',
                    value: _https,
                    onChanged: (v) => setState(() => _https = v),
                  ),
                ]),
                if (_message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
                    child: Text(
                      _message,
                      style: TextStyle(
                        fontSize: 13,
                        color: _failed
                            ? const Color(0xFFC0392B)
                            : const Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                if (widget.existing != null) ...[
                  const SizedBox(height: 22),
                  SheetGroup(dark: dark, children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _delete,
                      child: SizedBox(
                        height: 48,
                        child: Center(
                          child: Text(
                            '删除线路',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFFE5484D)
                                  .withValues(alpha: dark ? 0.9 : 1),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
