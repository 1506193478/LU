/// Emby 各种地址的拼接。
///
/// 单独一个文件、不依赖 Flutter，是为了能用 `dart tool/emby_url_probe.dart`
/// 直接跑：播放地址拼错一个 `?` 或漏了 `api_key`，表现出来就是"点开一片黑"，
/// 在沙箱里没法靠跑起来发现。
library;

/// 查询串拼接：自己决定用 `?` 还是 `&`，别让调用方手写。
String _withQuery(String base, List<String> params) {
  final meaningful = params.where((p) => p.isNotEmpty).toList();
  if (meaningful.isEmpty) return base;
  final separator = base.contains('?') ? '&' : '?';
  return '$base$separator${meaningful.join('&')}';
}

String _tokenParam(String? accessToken) =>
    accessToken == null || accessToken.isEmpty ? '' : 'api_key=$accessToken';

/// 封面 / 剧照。
///
/// `tag` 一定要带上：Emby 拿它做缓存键，不带的话每次请求都会重新生成缩略图，
/// 一个几十集的列表滚起来服务端会很难受。
String embyImageUrl({
  required String serverUrl,
  required String itemId,
  String? accessToken,
  int maxHeight = 400,
  String? tag,
}) {
  final base = '$serverUrl/Items/$itemId/Images/Primary';
  return _withQuery(base, [
    'maxHeight=$maxHeight',
    'quality=90',
    if (tag != null && tag.isNotEmpty) 'tag=$tag',
    _tokenParam(accessToken),
  ]);
}

/// 原盘直连：服务端不转码，mpv 自己解。绝大多数片源都该走这条。
String embyDirectStreamUrl({
  required String serverUrl,
  required String itemId,
  String? accessToken,
}) {
  final base = '$serverUrl/Videos/$itemId/stream';
  return _withQuery(base, [
    'static=true',
    'MediaSourceId=$itemId',
    _tokenParam(accessToken),
  ]);
}

/// 转码兜底：让服务端出 HLS。mpv 解不了源编码时才用。
String embyHlsStreamUrl({
  required String serverUrl,
  required String itemId,
  String? accessToken,
}) {
  final base = '$serverUrl/Videos/$itemId/master.m3u8';
  return _withQuery(base, [
    'MediaSourceId=$itemId',
    'VideoCodec=h264',
    'AudioCodec=aac,mp3',
    'TranscodingMaxAudioChannels=2',
    'SegmentContainer=ts',
    _tokenParam(accessToken),
  ]);
}
