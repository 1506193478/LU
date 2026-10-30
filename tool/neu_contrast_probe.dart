// 拟态配色对比度自检（纯 Dart，不依赖 Flutter 运行时）。
//
// 背景：手机端这一版默认走「浅色 + 拟态」，底色从主题的 #F5F6F8 换成了
// 拟态固定的 #E8EAF0，凸起面 #EFF1F6、凹槽 #DDDFE5。这几个值和主题的
// onSurface / onSurfaceVariant 之前从没一起验过，必须算一遍——
// 「浅色下看不清字」是这个项目踩过的坑。
//
// 跑法：dart --packages=.dart_tool/package_config.json tool/neu_contrast_probe.dart

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

int _pass = 0;
int _fail = 0;

void check(String label, int fg, int bg, {double min = 4.5}) {
  final double c = contrast(fg, bg);
  final bool ok = c >= min;
  if (ok) {
    _pass++;
  } else {
    _fail++;
  }
  print('${ok ? 'PASS' : 'FAIL'}  ${c.toStringAsFixed(2)}:1  '
      '(需 ${min < 2 ? min.toStringAsFixed(2) : min.toStringAsFixed(1)})  $label');
}

// ---- 拟态色板（对应 lib/bean/widget/clay_neu.dart 的 NeuTokens） ----
const int neuLightBase = 0xE8EAF0;
const int neuLightRaised = 0xEFF1F6;
const int neuLightRecess = 0xDDDFE5;

const int neuDarkBase = 0x292C33;
const int neuDarkRaised = 0x33363D;
const int neuDarkRecess = 0x272A30;

// 主题文字色（immersive_theme.dart / ColorScheme.fromSeed 的实际取值近似）
const int lightOnSurface = 0x1A1C1F;
const int lightOnSurfaceVariant = 0x49454F;
const int lightPrimary = 0x6A4FBF; // 浅色模式 primary（深紫，用于选中态文字）
const int darkOnSurface = 0xE4E2E8;
const int darkOnSurfaceVariant = 0xC9C5D0;
const int darkPrimary = 0xB69CFF;

void main() {
  print('=== 浅色拟态 ===');
  // 正文压在三种面上
  check('正文 / 底色', lightOnSurface, neuLightBase);
  check('正文 / 凸起面', lightOnSurface, neuLightRaised);
  check('正文 / 凹槽', lightOnSurface, neuLightRecess);
  // 次要文字：卡片里的放送日、侧栏说明文字
  check('次要文字 / 底色', lightOnSurfaceVariant, neuLightBase, min: 3.0);
  check('次要文字 / 凸起面', lightOnSurfaceVariant, neuLightRaised, min: 3.0);
  check('次要文字 / 凹槽', lightOnSurfaceVariant, neuLightRecess, min: 3.0);
  // 强调色文字：选中态导航项、标签
  check('强调文字 / 底色', lightPrimary, neuLightBase);
  check('强调文字 / 凹槽', lightPrimary, neuLightRecess);

  print('');
  print('=== 深色拟态 ===');
  check('正文 / 底色', darkOnSurface, neuDarkBase);
  check('正文 / 凸起面', darkOnSurface, neuDarkRaised);
  check('正文 / 凹槽', darkOnSurface, neuDarkRecess);
  check('次要文字 / 底色', darkOnSurfaceVariant, neuDarkBase, min: 3.0);
  check('次要文字 / 凸起面', darkOnSurfaceVariant, neuDarkRaised, min: 3.0);
  check('次要文字 / 凹槽', darkOnSurfaceVariant, neuDarkRecess, min: 3.0);
  check('强调文字 / 底色', darkPrimary, neuDarkBase);
  check('强调文字 / 凹槽', darkPrimary, neuDarkRecess);

  print('');
  print('=== 层次可辨性（凸起/凹槽 vs 底色） ===');
  // 浅色靠「填色差」立起来，所以要 >=1.05 才看得出是块浮起的板。
  check('浅色 凸起 vs 底', neuLightRaised, neuLightBase, min: 1.05);
  check('浅色 凹槽 vs 底', neuLightRecess, neuLightBase, min: 1.05);
  check('深色 凸起 vs 底', neuDarkRaised, neuDarkBase, min: 1.05);
  // 深色凹槽只压暗 5%，填色差天生小；它的深度主要来自 _NeuEdgePainter
  // 画的那圈内阴影（insetDark 0x33000000），所以这里只要求"能分出一点"。
  check('深色 凹槽 vs 底（靠内阴影撑）', neuDarkRecess, neuDarkBase, min: 1.02);

  print('');
  print(_fail == 0 ? 'ALL PASS ($_pass)' : '$_fail FAILED / ${_pass + _fail}');
}
