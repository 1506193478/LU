/// 一起看聊天里的内置表情。
///
/// 只用 Unicode 字符、不引入任何图片资源：走的是普通文字通道，对面哪怕是
/// 旧版本客户端也能正常显示。分组只是为了让常用的好找，没有语义。
class SyncPlayEmojiGroup {
  const SyncPlayEmojiGroup(this.label, this.emojis);

  final String label;
  final List<String> emojis;
}

List<SyncPlayEmojiGroup> buildSyncPlayEmojiGroups() => [
      SyncPlayEmojiGroup(
        '表情',
        '😀 😃 😄 😁 😆 😅 😂 🤣 😊 😇 🙂 😉 😍 🥰 😘 😋 😜 🤪 😝 🤗 '
                '🤭 🤔 🤨 😐 😑 😶 🙄 😏 😮 😲 🥺 😴'
            .split(' '),
      ),
      SyncPlayEmojiGroup(
        '手势',
        '👍 👎 👌 ✌️ 🤞 🤟 🤘 👏 🙌 🙏 💪 👋 🤝 ☝️ 👇 👈 👉 ✋ 🖐️ 🤙 '
                '🫰 🫶 🤌 🫡 🙇 🧎 🏃 💃 🕺 👀'
            .split(' '),
      ),
      SyncPlayEmojiGroup(
        '心情',
        '❤️ 🧡 💛 💚 💙 💜 🖤 🤍 💔 💕 💞 💓 💗 💖 ✨ ⭐ 🌟 💫 🔥 💥 '
                '💦 💨 🎉 🎊 💤 😭 😢 😤 😡 🤯 🥳'
            .split(' '),
      ),
      SyncPlayEmojiGroup(
        '其他',
        '🍜 🍚 🍺 ☕ 🍰 🍉 🍓 🎮 🎧 📺 💻 📱 🕐 🌙 ☀️ 🌧️ ❄️ 🎬 🎵 📷 '
                '🛋️ 🛏️ 🚀 🎁 🏆 ✅ ❓ ❗ 💯 🔔'
            .split(' '),
      ),
    ];
