// 粘土配色的对比度自检（纯 Dart，不依赖 Flutter 运行时）。
//
// 为什么是纯 Dart：沙箱里 `flutter test` 会触发 ech_http 的 native build hook，
// 而那一步要调 reg.exe，被安全策略拦掉了。所以这里用 WCAG 2.1 的相对亮度
// 公式手算一遍关键配色对，专门盯「浅色模式看不清字」这一类问题。
//
// 跑法：dart tool/light_mode_contrast_probe.dart

import 'dart:math' as math;

double _lin(int c) {
  final double s = c / 255;
  return s <= 0.04045 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4) as double;
}

double lum(int rgb) {
  final int r = (rgb >> 16) & 0xFF;
  final int g = (rgb >> 8) & 0xFF;
  final int b = rgb & 0xFF;
  return 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b);
}

double contrast(int a, int b) {
  final double la = lum(a);
  final double lb = lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

int lerp(int a, int b, double t) {
  int ch(int shift) {
    final int ca = (a >> shift) & 0xFF;
    final int cb = (b >> shift) & 0xFF;
    return (ca + (cb - ca) * t).round().clamp(0, 255);
  }

  return (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

int blend(int fg, double alpha, int bg) => lerp(bg, fg, alpha);

const int white = 0xFFFFFF;
const int black = 0x000000;
const int ink = 0x16121F; // ClayToneColors.fromSeed 的 fg
const int onSurface = 0x1A1C1F; // 浅色模式 onSurface 近似
const int onSurfaceVariant = 0x49454F;

int _pass = 0;
int _fail = 0;

void check(String label, int fg, int bg, {double min = 4.5}) {
  final double ratio = contrast(fg, bg);
  final bool ok = ratio >= min;
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  ${ratio.toStringAsFixed(2)}:1  '
      '#${fg.toRadixString(16).padLeft(6, '0').toUpperCase()} on '
      '#${bg.toRadixString(16).padLeft(6, '0').toUpperCase()}  $label');
}

String hex(int c) => '#${c.toRadixString(16).padLeft(6, '0').toUpperCase()}';

void main() {
  // 几支典型的 M3 语义色：浅色模式是 tone-40，深色模式是 tone-80。
  const Map<String, (int light, int dark)> seeds = {
    '紫（默认）': (0x7454C9, 0xD3BBFF),
    '红（danger）': (0xBA1A1A, 0xFFB4AB),
    '绿（success）': (0x3F6832, 0xA6D48E),
    '蓝（info）': (0x0061A4, 0x9FC9FF),
  };

  for (final MapEntry<String, (int, int)> e in seeds.entries) {
    for (final bool darkMode in <bool>[false, true]) {
      final int seed = darkMode ? e.value.$2 : e.value.$1;
      final String mode = darkMode ? '深色' : '浅色';

      // fromSeed 的两个分支（与 clay.dart 保持一致）
      final int lightStop;
      final int darkStop;
      final int fg;
      final int strong;
      if (darkMode) {
        lightStop = lerp(seed, white, 0.16);
        darkStop = lerp(seed, black, 0.20);
        fg = lum(seed) > 0.30 ? ink : white;
        strong = lerp(seed, white, 0.04);
      } else {
        final int pastel = lerp(seed, white, 0.55);
        lightStop = lerp(pastel, white, 0.12);
        darkStop = lerp(pastel, black, 0.12);
        fg = ink;
        strong = lerp(seed, black, 0.06);
      }

      print('--- $mode模式 / ${e.key} seed ${hex(seed)} ---');
      check('块上文字 / 受光端', fg, lightStop);
      check('块上文字 / 背光端', fg, darkStop);
      // 实色：进度轨、选中遮罩。压在白面板（浅色）/ 深面板（深色）上。
      final int panel = darkMode ? 0x15171C : 0xFFFFFF;
      check('实色 / 面板底色', strong, panel, min: 3.0);
      // 实色当文字用（提示胶囊、偏移胶囊）
      final int tint = darkMode
          ? lerp(0x23252D, darkStop, 0.42)
          : lerp(0xFFFFFF, lightStop, 0.16);
      // 深色模式的正文色是浅的，浅色模式是深的——别拿同一套常量量两种模式。
      final int onS = darkMode ? 0xE4E2E8 : onSurface;
      final int onSV = darkMode ? 0xC9C5D0 : onSurfaceVariant;
      check('染色底上的强调文字', darkMode ? lightStop : strong, tint);
      check('正文 / 染色底', onS, tint);
      check('次要文字 / 染色底', onSV, tint, min: 3.0);
      print('');
    }
  }

  // 一起看大厅：浅色模式的玻璃面板 + 页底
  print('--- 浅色模式 / 一起看大厅 ---');
  const int lightPage = 0xF5F6F8;
  final int glass = blend(white, 0.88, lightPage);
  check('正文 / 玻璃面板', onSurface, glass);
  check('次要文字 / 玻璃面板', onSurfaceVariant, glass, min: 3.0);
  check('正文 / 页底', onSurface, lightPage);
  // 延迟徽标（这次把 Colors.green/orange/red 换成了压深版）
  check('延迟 good  #2E7D32', 0x2E7D32, glass);
  check('延迟 warn  #A86200', 0xA86200, glass);
  check('延迟 bad   #B3261E', 0xB3261E, glass);
  print('--- 对照：旧配色（仅说明问题） ---');
  check('旧 Colors.green', 0x4CAF50, glass);
  check('旧 Colors.orange', 0xFF9800, glass);
  print('--- 对照：旧「深紫底白字」强调按钮 ---');
  check('白字 / #8B6DF0', 0xFFFFFF, 0x8B6DF0);

  print('');
  print(_fail == 0 ? 'ALL PASS ($_pass)' : '$_fail FAILED / ${_pass + _fail}');
}
