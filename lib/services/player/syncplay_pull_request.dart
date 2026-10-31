/// 「一起看」的求同步信令：后来加入的成员想要房间当前播放的内容。
///
/// 大厅里点「拉取正在播放」广播一条 `XLPULL1|`，房间里正在播放的成员
/// （播放器端）收到后，把自己的番剧信息按 [SyncPlayPlayRequest] 的分片
/// 协议**定向**回给请求者，请求者那边自动拉起播放器。
///
/// 信令本身只需要一个前缀——不带任何参数，因为「谁在求」写在聊天消息的
/// 发送者字段里，服务端会原样转发。内容为空时也整条发出去，让两端好做
/// 日志排查；它不会进任何一端的聊天记录。
class SyncPlayPullRequest {
  const SyncPlayPullRequest._();

  static const String prefix = 'XLPULL1|';

  static String encode() => prefix;

  static bool isPull(String text) => text.startsWith(prefix);
}
