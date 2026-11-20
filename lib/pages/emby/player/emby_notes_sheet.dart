import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:XL/services/emby/emby_video_notes.dart';

/// 视频笔记面板：列出当前影片的笔记，可新建（截图 + 文字），点击跳时间点。
class EmbyNotesSheet extends StatefulWidget {
  const EmbyNotesSheet({
    super.key,
    required this.videoKey,
    required this.videoTitle,
    required this.position,
    required this.onJump,
    required this.capture,
  });

  /// 影片稳定标识（item.id）。
  final String videoKey;
  final String videoTitle;

  /// 打开面板时的当前播放时间，新建笔记用它作时间点。
  final Duration position;

  /// 点笔记跳到对应时间点。
  final ValueChanged<Duration> onJump;

  /// 取当前帧截图（可为 null，表示内核不支持）。
  final Future<Uint8List?> Function() capture;

  @override
  State<EmbyNotesSheet> createState() => _EmbyNotesSheetState();
}

class _EmbyNotesSheetState extends State<EmbyNotesSheet> {
  final EmbyVideoNotes _store = EmbyVideoNotes.instance;

  List<EmbyVideoNote> get _notes => _store.notesFor(widget.videoKey);

  Future<void> _add() async {
    final textController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建视频笔记'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                autofocus: true,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: '记下这一刻的想法…',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      textController.dispose();
      return;
    }
    final note = textController.text.trim();
    textController.dispose();

    // 取当前帧：时间点用打开面板时的 position。
    Uint8List? shot;
    try {
      shot = await widget.capture();
    } catch (_) {
      shot = null;
    }
    await _store.add(
      videoKey: widget.videoKey,
      videoTitle: widget.videoTitle,
      position: widget.position,
      note: note.isEmpty ? '（无文字）' : note,
      screenshot: shot,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final notes = _notes;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.only(bottom: 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '视频笔记',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_rounded, color: Colors.white),
                    tooltip: '新建笔记',
                    onPressed: _add,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            if (notes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Text('还没有笔记，点 + 记录这一刻',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: notes.length,
                  itemBuilder: (context, index) {
                    final n = notes[index];
                    return ListTile(
                      leading: n.imagePath != null && File(n.imagePath!).existsSync()
                          ? SizedBox(
                              width: 56,
                              height: 40,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.file(
                                  File(n.imagePath!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.image_outlined, color: Colors.white54),
                                ),
                              ),
                            )
                          : const Icon(Icons.sticky_note_2_outlined, color: Colors.white54),
                      title: Text(
                        n.note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      subtitle: Text(n.positionLabel,
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      onTap: () {
                        widget.onJump(Duration(milliseconds: n.positionMs));
                        Navigator.of(context).pop();
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 18),
                        onPressed: () {
                          _store.remove(n.id);
                          setState(() {});
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
