import 'package:XL/services/player/syncplay_sticker_message.dart';

/// 表情包协议的离线自检：跑一遍编码 → 分片 → 拼装 → 解码。
///
/// 用法（绕过 native build hook）：
/// `dart --packages=.dart_tool/package_config.json tool/sticker_proto_probe.dart`
void main() {
  var ok = true;
  void check(String label, bool value, [String? detail]) {
    if (!value) ok = false;
    print('${value ? 'PASS' : 'FAIL'}  $label${detail == null ? '' : '  $detail'}');
  }

  const SyncPlayStickerMessage builtin =
      SyncPlayStickerMessage(packId: 'lu_clay', stickerId: 'happy');
  final String single = builtin.encodeSingle();
  final SyncPlayStickerMessage? back =
      SyncPlayStickerMessage.tryDecodeChat(single);
  check('内置包单条编码', single.length <= 150, 'len=${single.length}');
  check(
    '内置包单条解码',
    back?.packId == 'lu_clay' && back?.stickerId == 'happy' && back!.isBuiltin,
    single,
  );

  const SyncPlayStickerMessage short =
      SyncPlayStickerMessage(packId: 'p1', stickerId: '07', url: 'https://a.cn/7.png');
  final List<String> shortChunks = short.encodeChunks(messageId: 'zzzz');
  check('短地址只切一片', shortChunks.length == 1, shortChunks.first);

  final SyncPlayStickerMessage long = SyncPlayStickerMessage(
    packId: 'my_pack_2026',
    stickerId: 'sticker_07',
    url:
        'https://cdn.example.com/stickers/my_pack_2026/very/deep/path/with-a-long-folder-name/sticker_07@2x.webp?token=abcdefghijklmnop&v=3',
  );
  final List<String> chunks = long.encodeChunks(messageId: 'abcd');
  check('长地址自动分片', chunks.length >= 2, 'chunks=${chunks.length}');
  check(
    '每片都不超 150 字符',
    chunks.every((c) => c.length <= SyncPlayStickerMessage.maxChatLength),
    chunks.map((c) => c.length).join(','),
  );

  final SyncPlayStickerAssembler assembler = SyncPlayStickerAssembler();
  SyncPlayStickerMessage? assembled;
  for (final String chunk in chunks) {
    final SyncPlayStickerMessage? result = assembler.add('alice', chunk);
    if (result != null) assembled = result;
  }
  check(
    '分片拼装还原',
    assembled?.packId == long.packId &&
        assembled?.stickerId == long.stickerId &&
        assembled?.url == long.url,
    assembled?.url ?? 'null',
  );

  final SyncPlayStickerAssembler partial = SyncPlayStickerAssembler();
  final SyncPlayStickerMessage? firstOnly = partial.add('bob', chunks.first);
  check('只收到一片时不提前渲染', firstOnly == null);

  check('普通文字不误判', SyncPlayStickerMessage.tryDecodeChat('今天这集好强') == null);
  check(
    '坏协议不崩',
    SyncPlayStickerMessage.tryDecodeChat('LUSTK1|bad') == null &&
        SyncPlayStickerMessage.tryDecodeChat('LUSTK1|abcd/1/1|{oops') == null,
  );

  print(ok ? '\nALL PASS' : '\nHAS FAILURES');
}
