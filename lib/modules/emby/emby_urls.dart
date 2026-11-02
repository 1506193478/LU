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

/// `MediaSourceId` 只在拿到真实媒体源 id 时才写。
///
/// 这里踩过一个能把整块功能判死刑的坑：早期版本把条目 id 当成媒体源 id
/// 硬拼进去（`MediaSourceId=$itemId`）。Emby 4.9 之后媒体源 id 变成了
/// `mediasource_<itemId>` 这种带前缀的形式，服务端对不上就直接
/// **HTTP 400 `Value cannot be null. (Parameter 'mediaSource')`**——
/// 直连和 HLS 两条路一起死，播放器拿到的是一段纯文本错误，用户看到的就是黑屏。
///
/// 现在的策略：先问 `PlaybackInfo` 要真实 id；要不到就**整个参数不写**。
/// 实测不写时服务端会自己挑唯一媒体源，同样能出 206。
String _mediaSourceParam(String? mediaSourceId) =>
    mediaSourceId == null || mediaSourceId.isEmpty
        ? ''
        : 'MediaSourceId=$mediaSourceId';

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
  String type = 'Primary',
}) {
  final base = '$serverUrl/Items/$itemId/Images/$type';
  return _withQuery(base, [
    'maxHeight=$maxHeight',
    'quality=90',
    if (tag != null && tag.isNotEmpty) 'tag=$tag',
    _tokenParam(accessToken),
  ]);
}

/// 背景大图。详情页顶部的通栏主视觉用它，没有 backdrop 时调用方退回封面。
String embyBackdropUrl({
  required String serverUrl,
  required String itemId,
  String? accessToken,
  int maxWidth = 1600,
  String? tag,
}) {
  final base = '$serverUrl/Items/$itemId/Images/Backdrop';
  return _withQuery(base, [
    'maxWidth=$maxWidth',
    'quality=85',
    if (tag != null && tag.isNotEmpty) 'tag=$tag',
    _tokenParam(accessToken),
  ]);
}

/// 外挂字幕（含内封轨道的「流式」地址）。
///
/// Emby 的写法是 `/Videos/{id}/{mediaSourceId}/Subtitles/{index}/Stream.{ext}`，
/// 返回的就是一条可以直接喂给 mpv 的字幕文件。`codec` 是 MediaStream 上的
/// `Codec`（`subrip` / `ass` / `pgssub` …），Emby 对 `subrip` 会返回 `.srt`，
/// 所以这里做个映射，避免 `Stream.subrip` 这种不认的后缀。
String embySubtitleUrl({
  required String serverUrl,
  required String itemId,
  required int index,
  String? mediaSourceId,
  String? codec,
  String? accessToken,
}) {
  final source = (mediaSourceId != null && mediaSourceId.isNotEmpty)
      ? mediaSourceId
      : itemId;
  final base =
      '$serverUrl/Videos/$itemId/$source/Subtitles/$index/Stream.${_subtitleExt(codec)}';
  return _withQuery(base, [_tokenParam(accessToken)]);
}

String _subtitleExt(String? codec) => switch ((codec ?? '').toLowerCase()) {
      'subrip' || 'srt' => 'srt',
      'ass' || 'ssa' => 'ass',
      'webvtt' || 'vtt' => 'vtt',
      'mov_text' || 'mp4' => 'vtt',
      'pgssub' || 'pgs' || 'hdmv_pgs_subtitle' => 'sup',
      'dvdsub' || 'dvd_subtitle' => 'sub',
      final other when other.isNotEmpty => other,
      _ => 'srt',
    };

/// 原盘直连：服务端不转码，mpv 自己解。绝大多数片源都该走这条。
String embyDirectStreamUrl({
  required String serverUrl,
  required String itemId,
  String? accessToken,
  String? mediaSourceId,
}) {
  final base = '$serverUrl/Videos/$itemId/stream';
  return _withQuery(base, [
    'static=true',
    _mediaSourceParam(mediaSourceId),
    _tokenParam(accessToken),
  ]);
}

/// 转码兜底：让服务端出 HLS。mpv 解不了源编码、或者用户主动限制码率时才用。
///
/// [maxBitrateBps] 是「转码与串流」页里的画质上限，0 表示不限（服务端按
/// 自己的转码策略挑）。Emby 认的是比特每秒，UI 上填的是 Mbps，换算在调用方做。
String embyHlsStreamUrl({
  required String serverUrl,
  required String itemId,
  String? accessToken,
  String? mediaSourceId,
  int maxBitrateBps = 0,
}) {
  final base = '$serverUrl/Videos/$itemId/master.m3u8';
  return _withQuery(base, [
    _mediaSourceParam(mediaSourceId),
    'VideoCodec=h264',
    'AudioCodec=aac,mp3',
    'TranscodingMaxAudioChannels=2',
    'SegmentContainer=ts',
    if (maxBitrateBps > 0) ...[
      'MaxStreamingBitrate=$maxBitrateBps',
      'VideoBitrate=${maxBitrateBps > 1000000 ? maxBitrateBps - 384000 : maxBitrateBps}',
      'AudioBitrate=192000',
    ],
    _tokenParam(accessToken),
  ]);
}
