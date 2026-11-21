import 'package:flutter/material.dart';

import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/services/notification/lu_notification_center.dart';
import 'package:XL/theme/ios_interaction.dart';
import 'package:XL/utils/motion.dart';

/// 通知中心（对齐 Animeko「通知中心 + 分类设置」）：
/// 本地事件聚合列表，支持分类筛选、全部已读、左滑删除、按类型开关。
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final LuNotificationCenter _center = LuNotificationCenter.instance;

  /// 当前筛选：null = 全部，否则是分类 id。
  String? _filter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PvColors.page(context),
      appBar: AppBar(
        leading: const KzBackButton(),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('通知中心'),
        actions: [
          KzPressable(
            pressedOpacity: 0.5,
            onTap: () => _center.markAllRead(),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Text('全部已读'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFilterBar(context),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _FilterChip(
              label: '全部',
              selected: _filter == null,
              onTap: () => setState(() => _filter = null),
            ),
            const SizedBox(width: 8),
            for (final c in LuNotificationCategory.values) ...[
              _FilterChip(
                label: c.label,
                selected: _filter == c.id,
                onTap: () => setState(() => _filter = c.id),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return ValueListenableBuilder<int>(
      valueListenable: _center.revision,
      builder: (context, _, __) {
        final all = _center.all;
        final items = _filter == null
            ? all
            : all.where((n) => n.categoryId == _filter).toList();
        if (items.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.notifications_none_rounded,
                    size: 56, color: Color(0xFF8E8E93)),
                SizedBox(height: 12),
                Text('暂无通知',
                    style: TextStyle(fontSize: 15, color: Color(0xFF8E8E93))),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final n = items[index];
            return _NotificationTile(
              notification: n,
              onTap: () => _center.markRead(n.id),
              onDelete: () => _center.remove(n.id),
            );
          },
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KzPressable(
      onTap: onTap,
      pressedOpacity: 0.7,
      child: AnimatedContainer(
        duration: KazumiMotion.instant,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? PvColors.blue
              : (PvColors.isDark(context)
                  ? const Color(0xFF1C1C1E)
                  : const Color(0xFFE5E5EA)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : PvColors.ink(context),
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
    required this.onDelete,
  });

  final LuNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  IconData get _icon => switch (notification.category) {
        LuNotificationCategory.system => Icons.notifications_rounded,
        LuNotificationCategory.update => Icons.system_update_rounded,
        LuNotificationCategory.download => Icons.download_rounded,
        LuNotificationCategory.playback => Icons.play_circle_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final time = DateTime.fromMillisecondsSinceEpoch(notification.timestamp);
    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return true;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: PvColors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      child: KzPressable(
        onTap: onTap,
        pressedOpacity: 0.85,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: PvColors.card(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Color(notification.category.color).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_icon,
                    size: 20, color: Color(notification.category.color)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: notification.read
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                              color: PvColors.ink(context),
                            ),
                          ),
                        ),
                        if (!notification.read)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: PvColors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: PvText.rowSub(context),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatTime(time),
                      style: TextStyle(
                        fontSize: 12,
                        color: PvColors.ink3(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final sameDay = t.year == now.year &&
        t.month == now.month &&
        t.day == now.day;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    if (sameDay) return '今天 $hh:$mm';
    return '${t.month}月${t.day}日 $hh:$mm';
  }
}

/// 通知分类设置页（按类型开关）。
class NotificationCategoriesPage extends StatefulWidget {
  const NotificationCategoriesPage({super.key});

  @override
  State<NotificationCategoriesPage> createState() =>
      _NotificationCategoriesPageState();
}

class _NotificationCategoriesPageState
    extends State<NotificationCategoriesPage> {
  final LuNotificationCenter _center = LuNotificationCenter.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PvColors.page(context),
      appBar: AppBar(
        leading: const KzBackButton(),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('通知分类'),
      ),
      body: SafeArea(
        child: ValueListenableBuilder<int>(
          valueListenable: _center.revision,
          builder: (context, _, __) {
            return ListView(
              padding: const EdgeInsets.only(top: 10, bottom: 32),
              children: [
                PvGroup(
                  children: [
                    for (final c in LuNotificationCategory.values)
                      PvRow(
                        icon: _iconOf(c),
                        iconColor: Color(c.color),
                        title: c.label,
                        trailingWidget: PvSwitch(
                          value: _center.categoryEnabled(c),
                          onChanged: (v) =>
                              _center.setCategoryEnabled(c, v),
                        ),
                        trailing: PvRowTrailing.widget,
                        showDivider:
                            c != LuNotificationCategory.values.last,
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Text(
                    '关闭后，该类型的本地事件不再进入通知中心。',
                    style: PvText.rowSub(context),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  IconData _iconOf(LuNotificationCategory c) => switch (c) {
        LuNotificationCategory.system => Icons.notifications_rounded,
        LuNotificationCategory.update => Icons.system_update_rounded,
        LuNotificationCategory.download => Icons.download_rounded,
        LuNotificationCategory.playback => Icons.play_circle_outline_rounded,
      };
}
