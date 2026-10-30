/// 标题归一化与相似度打分。
///
/// 中文番剧标题里混着全角标点、括号、波浪号、季数后缀，直接做字符串比较
/// 几乎不可能命中，所以先归一化再按「完全相等 → 互相包含 → 公共前缀」分级。
library;

/// 去掉空白与标点，只保留中日文、拉丁字母和数字。
///
/// 例：`【我推的孩子】` → `我推的孩子`，`孤独摇滚！` → `孤独摇滚`。
String normalizeTitle(String input) {
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    final isAsciiDigit = rune >= 0x30 && rune <= 0x39;
    final isAsciiLower = rune >= 0x61 && rune <= 0x7A;
    final isKana = rune >= 0x3040 && rune <= 0x30FF;
    final isCjk = (rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0xF900 && rune <= 0xFAFF);
    if (isAsciiDigit || isAsciiLower || isKana || isCjk) {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// 0–100 的相似度。传入前请先各自 [normalizeTitle]。
int titleSimilarity(String a, String b) {
  if (a.isEmpty || b.isEmpty) {
    return 0;
  }
  if (a == b) {
    return 100;
  }
  if (a.contains(b) || b.contains(a)) {
    final shorter = a.length < b.length ? a.length : b.length;
    final longer = a.length < b.length ? b.length : a.length;
    // 长度越接近给分越高，避免「孤独摇滚」压过「孤独摇滚第二季」的区分失效。
    return 60 + (40 * shorter ~/ longer);
  }
  var common = 0;
  final limit = a.length < b.length ? a.length : b.length;
  while (common < limit && a[common] == b[common]) {
    common++;
  }
  if (common == 0) {
    return 0;
  }
  final base = a.length > b.length ? a.length : b.length;
  return 40 * common ~/ base;
}

/// 查询词与一组候选标题的最佳得分。
int bestTitleScore(String query, Iterable<String> candidates) {
  final normalizedQuery = normalizeTitle(query);
  if (normalizedQuery.isEmpty) {
    return 0;
  }
  var best = 0;
  for (final candidate in candidates) {
    final normalized = normalizeTitle(candidate);
    if (normalized.isEmpty) {
      continue;
    }
    final score = titleSimilarity(normalizedQuery, normalized);
    if (score > best) {
      best = score;
    }
  }
  return best;
}
