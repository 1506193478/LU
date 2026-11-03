import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:XL/pages/emby/emby_preview_style.dart';

/// 底部卡片式表单的共用零件。
///
/// 服务器表单、备用线路、线路编辑三个页面长得一模一样（同一张设计稿的
/// 三个层级），所以顶栏 / 分组白卡 / 输入行 / 开关行全部放这里，谁也别
/// 各写一套——不然「保存」竖排、胶囊高度不一致这类问题会反复出现。

/// 顶栏：左返回 / 居中标题 / 右侧「保存」。
///
/// 备用线路页的顶栏是「标题居中 + 右侧两颗图标」，布局不一样，所以它自己
/// 画（见 `emby_backup_lines.dart` 的 `_BarIcon`），没有往这里塞参数。
class SheetTopBar extends StatelessWidget {
  const SheetTopBar({
    super.key,
    required this.title,
    this.onClose,
    this.onSave,
    this.busy = false,
    this.saveLabel = '保存',
  });

  final String title;
  final VoidCallback? onClose;
  final VoidCallback? onSave;
  final bool busy;
  final String saveLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: onClose == null
                ? null
                : IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 19,
                      color: Color(0xFF007AFF),
                    ),
                    onPressed: onClose,
                  ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: PvColors.ink(context),
              ),
            ),
          ),
          // 「保存」必须横着排。之前给 62 宽 + TextButton 自带的 16 内边距，
          // 系统字体放大到 1.3 倍以上时两个字的宽度就超了，直接竖着断成
          // 「保 / 存」。这里固定 76 宽、单行不换行、右对齐。
          SizedBox(
            width: 76,
            child: busy
                ? const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onSave,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Text(
                          saveLabel,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: onSave == null
                                ? const Color(0xFF007AFF).withValues(alpha: 0.4)
                                : const Color(0xFF007AFF),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 分组上方的小灰字（`服务器地址` / `登录信息`）。
class SheetGroupLabel extends StatelessWidget {
  const SheetGroupLabel({super.key, required this.dark, required this.text});

  final bool dark;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 16, 6, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: dark
              ? Colors.white.withValues(alpha: 0.4)
              : const Color(0xFF8A8A8E),
        ),
      ),
    );
  }
}

/// iOS 风白卡：圆角 12，行间一条细线。
class SheetGroup extends StatelessWidget {
  const SheetGroup({super.key, required this.dark, required this.children});

  final bool dark;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1F1E22) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 0.6,
                indent: 14,
                color: dark ? Colors.white10 : const Color(0xFFEBEBEF),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 标签 + 右对齐输入框（34 高浅灰胶囊）。
class SheetFieldRow extends StatelessWidget {
  const SheetFieldRow({
    super.key,
    required this.dark,
    required this.label,
    required this.hint,
    required this.controller,
    this.obscure = false,
    this.keyboard,
    this.inputFormatters,
    this.suffix,
  });

  final bool dark;
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscure;
  final TextInputType? keyboard;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    // 输入区不铺满整行：34 高的浅灰胶囊，标签和胶囊之间留 10，行高 48。
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 14),
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(fontSize: 15.5, color: PvColors.ink(context)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 34,
              padding: const EdgeInsets.only(left: 10, right: 4),
              decoration: BoxDecoration(
                color: dark
                    ? Colors.white.withValues(alpha: 0.07)
                    : const Color(0xFFEFEFF3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      obscureText: obscure,
                      keyboardType: keyboard,
                      inputFormatters: inputFormatters,
                      textAlign: TextAlign.right,
                      textAlignVertical: TextAlignVertical.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: PvColors.ink(context),
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        hintText: hint,
                        hintStyle: TextStyle(
                          fontSize: 15,
                          color: dark
                              ? Colors.white24
                              : const Color(0xFFB4B4BA),
                        ),
                      ),
                    ),
                  ),
                  if (suffix != null) suffix!,
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// 左侧标签 + 右侧 iOS 开关。
class SheetSwitchRow extends StatelessWidget {
  const SheetSwitchRow({
    super.key,
    required this.dark,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final bool dark;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 15.5, color: PvColors.ink(context)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Transform.scale(
            scale: 0.86,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.white,
              activeTrackColor: const Color(0xFF34C759),
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: dark
                  ? Colors.white.withValues(alpha: 0.18)
                  : const Color(0xFFE4E4E9),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

/// 可点的箭头行（备用线路 / 高级设置）。
class SheetArrowRow extends StatelessWidget {
  const SheetArrowRow({
    super.key,
    required this.dark,
    required this.label,
    this.value,
    this.expanded,
    this.onTap,
  });

  final bool dark;
  final String label;
  final String? value;
  final bool? expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 15.5, color: PvColors.ink(context)),
            ),
          ),
          if (value != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                value!,
                style: TextStyle(
                  fontSize: 15,
                  color: dark
                      ? Colors.white.withValues(alpha: 0.4)
                      : const Color(0xFF8A8A8E),
                ),
              ),
            ),
          if (expanded != null)
            Icon(
              expanded!
                  ? Icons.expand_more_rounded
                  : Icons.chevron_right_rounded,
              size: 20,
              color: const Color(0xFF007AFF),
            )
          else
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: dark ? Colors.white24 : const Color(0xFFC7C7CC),
            ),
          const SizedBox(width: 12),
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: row,
    );
  }
}

/// 高级设置展开后嵌在卡里的那一行（标题 + 说明 + 开关）。
class SheetNestedSwitchRow extends StatelessWidget {
  const SheetNestedSwitchRow({
    super.key,
    required this.dark,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final bool dark;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 4, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 15, color: PvColors.ink(context)),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: dark
                        ? Colors.white.withValues(alpha: 0.4)
                        : const Color(0xFF8A8A8E),
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.86,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.white,
              activeTrackColor: const Color(0xFF34C759),
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: dark
                  ? Colors.white.withValues(alpha: 0.18)
                  : const Color(0xFFE4E4E9),
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡片下方的一行说明文字。
class SheetHint extends StatelessWidget {
  const SheetHint({super.key, required this.dark, required this.text});

  final bool dark;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 7, 6, 0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: dark
              ? Colors.white.withValues(alpha: 0.35)
              : const Color(0xFF8A8A8E),
        ),
      ),
    );
  }
}
