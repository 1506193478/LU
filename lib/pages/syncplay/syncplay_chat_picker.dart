import 'package:flutter/material.dart';

import 'package:XL/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:XL/bean/dialog/dialog_helper.dart';
import 'package:XL/bean/widget/syncplay_sticker_view.dart';
import 'package:XL/pages/syncplay/syncplay_emoji_data.dart';
import 'package:XL/pages/syncplay/syncplay_sticker_packs.dart';
import 'package:XL/services/player/syncplay_sticker_message.dart';
import 'package:XL/bean/widget/clay.dart';

/// 最近用过的表情，只活在这个进程里——为了 16 个字符写一次磁盘不划算。
final List<String> _recentEmojis = <String>[];

/// 打开一起看的聊天面板：表情 / 表情包两个 tab。
///
/// 表情直接插到输入框光标处（走普通文字通道，旧版本客户端也能看），
/// 表情包通过 [onSticker] 立刻发出去。
Future<void> showSyncPlayChatPicker({
  required BuildContext context,
  required TextEditingController textController,
  required ValueChanged<SyncPlayStickerMessage> onSticker,
}) {
  return showAdaptiveBottomSheet<void>(
    context: context,
    maxHeightFactor: 0.64,
    builder: (_) => _SyncPlayChatPicker(
      textController: textController,
      onSticker: onSticker,
    ),
  );
}

class _SyncPlayChatPicker extends StatefulWidget {
  const _SyncPlayChatPicker({
    required this.textController,
    required this.onSticker,
  });

  final TextEditingController textController;
  final ValueChanged<SyncPlayStickerMessage> onSticker;

  @override
  State<_SyncPlayChatPicker> createState() => _SyncPlayChatPickerState();
}

class _SyncPlayChatPickerState extends State<_SyncPlayChatPicker> {
  static const int _recentLimit = 16;

  late final List<SyncPlayEmojiGroup> _groups = buildSyncPlayEmojiGroups();
  final SyncPlayStickerStore _store = SyncPlayStickerStore.instance;
  int _tab = 0;
  String _packId = syncPlayBuiltinStickerPack.id;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _pickEmoji(String emoji) {
    final TextEditingValue value = widget.textController.value;
    final TextSelection selection = value.selection;
    final int start = selection.isValid ? selection.start : value.text.length;
    final int end = selection.isValid ? selection.end : value.text.length;
    widget.textController.value = value.copyWith(
      text: value.text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
      composing: TextRange.empty,
    );
    setState(() {
      _recentEmojis
        ..remove(emoji)
        ..insert(0, emoji);
      if (_recentEmojis.length > _recentLimit) {
        _recentEmojis.removeRange(_recentLimit, _recentEmojis.length);
      }
    });
  }

  void _pickSticker(SyncPlayStickerPack pack, SyncPlaySticker sticker) {
    widget.onSticker(
      SyncPlayStickerMessage(
        packId: pack.id,
        stickerId: sticker.id,
        url: sticker.isAsset ? '' : sticker.url,
      ),
    );
    Navigator.of(context).maybePop();
  }

  Future<void> _openImport() async {
    await showAdaptiveBottomSheet<void>(
      context: context,
      maxHeightFactor: 0.62,
      builder: (_) => _StickerImportSheet(
        onImported: (pack) {
          if (!mounted) return;
          setState(() {
            _packId = pack.id;
            _tab = 1;
          });
        },
      ),
    );
  }

  Future<void> _confirmRemove(SyncPlayStickerPack pack) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ClayDialog(
        title: '移除表情包',
        icon: Icons.emoji_emotions_outlined,
        message: '移除「${pack.name}」后，收到这个包的表情会显示成占位图。',
        maxWidth: 460,
        actions: [
          ClayButton(
            tone: ClayTone.subtle,
            height: 44,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          ClayButton(
            tone: ClayTone.danger,
            height: 44,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _store.remove(pack.id);
    if (!mounted) return;
    setState(() {
      if (_packId == pack.id) _packId = syncPlayBuiltinStickerPack.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
            child: Row(
              children: [
                Text(
                  '聊天',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                _tabButton('表情', 0),
                const SizedBox(width: 8),
                _tabButton('表情包', 1),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: '关闭',
                ),
              ],
            ),
          ),
          Flexible(
            child: _tab == 0 ? _buildEmojiBody() : _buildStickerBody(),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    final ThemeData theme = Theme.of(context);
    final bool selected = _tab == index;
    return GestureDetector(
      onTap: () => setState(() => _tab = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.18)
              : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- 表情

  Widget _buildEmojiBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      children: [
        if (_recentEmojis.isNotEmpty) ...[
          _groupLabel('最近使用'),
          _emojiGrid(_recentEmojis),
          const SizedBox(height: 14),
        ],
        for (final SyncPlayEmojiGroup group in _groups) ...[
          _groupLabel(group.label),
          _emojiGrid(group.emojis),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _groupLabel(String label) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _emojiGrid(List<String> emojis) {
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      children: [
        for (final String emoji in emojis)
          SizedBox(
            width: 42,
            height: 42,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _pickEmoji(emoji),
              child: Center(
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 22, height: 1.1),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ----------------------------------------------------------- 表情包

  Widget _buildStickerBody() {
    final ThemeData theme = Theme.of(context);
    final List<SyncPlayStickerPack> packs = _store.packs;
    final SyncPlayStickerPack pack = _store.packOf(_packId) ?? packs.first;

    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: packs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final SyncPlayStickerPack item = packs[index];
              final bool selected = item.id == pack.id;
              return GestureDetector(
                onTap: () => setState(() => _packId = item.id),
                onLongPress: item.builtin ? null : () => _confirmRemove(item),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? theme.colorScheme.primary.withValues(alpha: 0.18)
                        : theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: [
                      SyncPlayStickerView(
                        sticker: item.stickers.first,
                        size: 24,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        item.name,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: pack.stickers.length,
            itemBuilder: (context, index) {
              final SyncPlaySticker sticker = pack.stickers[index];
              return GestureDetector(
                onTap: () => _pickSticker(pack, sticker),
                child: SyncPlayStickerView(sticker: sticker, size: 72),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  pack.builtin ? '长按表情包可移除自定义包' : '长按当前表情包可移除',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _openImport,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('导入表情包'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 导入表情包：填一个清单地址，或者直接粘贴 JSON。
class _StickerImportSheet extends StatefulWidget {
  const _StickerImportSheet({required this.onImported});

  final ValueChanged<SyncPlayStickerPack> onImported;

  @override
  State<_StickerImportSheet> createState() => _StickerImportSheetState();
}

class _StickerImportSheetState extends State<_StickerImportSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final String raw = _controller.text.trim();
    if (raw.isEmpty) return;
    setState(() => _busy = true);
    try {
      final SyncPlayStickerPack pack =
          await SyncPlayStickerStore.instance.importFrom(raw);
      if (!mounted) return;
      widget.onImported(pack);
      Navigator.of(context).maybePop();
      KazumiDialog.showToast(message: '已导入「${pack.name}」· ${pack.stickers.length} 张');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      KazumiDialog.showToast(
        message: '导入失败：${e is FormatException ? e.message : e}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: 18 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '导入表情包',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '填一个清单地址，或者直接粘贴清单 JSON。\n'
            '清单格式：{"name":"包名","stickers":[{"id":"01","url":"https://…/01.png"}]}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 6,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'https://…/pack.json 或 {…}',
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('导入'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
