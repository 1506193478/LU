/// 一起看里的「快捷反应」。
///
/// 走 Chat 通道发一条 `XLR1|<emoji>`，总共 6~7 个字符，远低于服务端 150
/// 字符的上限，不需要分片。收到的一方不进聊天列表当正文，只在画面上飘一条
/// 大字弹幕 —— 所以它必须能和普通聊天区分开。
class SyncPlayReaction {
  const SyncPlayReaction._();

  static const String prefix = 'XLR1|';

  /// 底栏上的一排按钮。
  ///
  /// 顺序按「一起看最常按」排：笑、惊、鼓掌、心动、困、哭。别随手调换，
  /// 房间里的老用户是凭位置按的。
  static const List<String> palette = <String>[
    '😂',
    '😱',
    '👏',
    '❤️',
    '😴',
    '😭',
  ];

  static String encode(String emoji) => '$prefix$emoji';

  static bool isReaction(String text) => text.startsWith(prefix);

  /// 不是本协议、或者内容不在 [palette] 里时返回 null。
  ///
  /// 白名单校验不能省：这个值会被直接画到别人屏幕上，不校验就等于让房间里
  /// 任何人往你画面上塞任意长度的文字。
  static String? tryParse(String text) {
    if (!isReaction(text)) {
      return null;
    }
    final String emoji = text.substring(prefix.length).trim();
    return palette.contains(emoji) ? emoji : null;
  }
}
