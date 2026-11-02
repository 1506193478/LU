import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:XL/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:XL/bean/widget/loading_indicator.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/pages/player/player_controller.dart';
import 'package:XL/pages/syncplay/syncplay_controller.dart'
    show kSyncPlayRoomNumberLength;
import 'package:XL/services/player/syncplay_client.dart';
import 'package:XL/services/player/syncplay_endpoint.dart';
import 'package:XL/services/storage/storage.dart';
import 'package:XL/utils/device.dart';

// Close each step before opening the next to avoid stacked modal routes.
enum _SyncPlayDestination { create, join, server }

Future<void> showSyncPlaySheet(
  BuildContext context, {
  required PlayerController playerController,
  required Future<void> Function(int episode, {int currentRoad, int offset})
      changeEpisode,
}) async {
  final _SyncPlayDestination? destination =
      await _showStep<_SyncPlayDestination>(
    context,
    (context) => _SyncPlayHomeSheet(playerController: playerController),
  );
  if (destination == null || !context.mounted) {
    return;
  }
  await _showStep<void>(
    context,
    (context) => switch (destination) {
      _SyncPlayDestination.create ||
      _SyncPlayDestination.join =>
        _SyncPlayRoomSheet(
          isCreate: destination == _SyncPlayDestination.create,
          playerController: playerController,
          changeEpisode: changeEpisode,
        ),
      _SyncPlayDestination.server => const _SyncPlayServerSheet(),
    },
  );
}

Future<T?> _showStep<T>(BuildContext context, WidgetBuilder builder) {
  return showAdaptiveBottomSheet<T>(
    context: context,
    maxHeightFactor: 0.8,
    compactLandscapeMaxHeightFactor: 0.95,
    builder: builder,
  );
}

String _readEndPoint() =>
    GStorage.getSetting<String>(SettingsKeys.syncPlayEndPoint);

/// 表单输入框：浅灰胶囊，聚焦时描一圈蓝。
///
/// 原来用的是 Material 的 `OutlineInputBorder` 大圆角描边框，跟一起看页里
/// 那些胶囊输入框完全不是一个东西，弹窗一开就显得像另一个 App。
InputDecoration _sheetFieldDecoration(
  BuildContext context, {
  required String hint,
  String? error,
}) {
  final bool dark = PvColors.isDark(context);
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(fontSize: 15, color: PvColors.searchHint(context)),
    errorText: error,
    errorStyle: const TextStyle(fontSize: 12, color: PvColors.red),
    isDense: true,
    filled: true,
    fillColor: PvColors.searchFill(context),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: PvColors.blue.withValues(alpha: dark ? 0.9 : 0.75),
        width: 1.4,
      ),
    ),
  );
}

/// 弹窗外壳：标题行 + 可滚动正文 + 底部动作。
///
/// 抓手由 [showAdaptiveBottomSheet] 那层画，这里只负责内容。
class _SyncPlaySheetScaffold extends StatelessWidget {
  const _SyncPlaySheetScaffold({
    required this.title,
    required this.description,
    required this.bodyBuilder,
    this.action,
    this.dangerAction,
  });

  final String title;
  final String description;
  final Widget Function(BuildContext context, bool compact) bodyBuilder;

  /// 底部主按钮（蓝色实心）。
  final Widget? action;

  /// 底部次按钮（浅红底红字），比如「断开连接」。
  final Widget? dangerAction;

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    final bool compact =
        size.width > size.height && !isDesktop() && size.shortestSide < 600;
    final bool showDescription = !(compact && keyboardInset > 0);

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 10, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: PvText.section(context)),
                      if (showDescription) ...[
                        const SizedBox(height: 2),
                        Text(
                          description,
                          style: PvText.rowSub(context).copyWith(fontSize: 12.5),
                        ),
                      ],
                    ],
                  ),
                ),
                PvIconBtn(
                  icon: Icons.close_rounded,
                  tooltip: '关闭',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: bodyBuilder(context, compact),
            ),
          ),
          if (action != null || dangerAction != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?action,
                  if (action != null && dangerAction != null)
                    const SizedBox(height: 9),
                  ?dangerAction,
                ],
              ),
            )
          else
            const SizedBox(height: 22),
        ],
      ),
    );
  }
}

/// 弹窗底部的蓝色主按钮，跟一起看页的「开始一起看」同一套。
class _SheetPrimaryButton extends StatelessWidget {
  const _SheetPrimaryButton({
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: PvColors.blue,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹窗底部的破坏性按钮：浅红底、红字。
class _SheetDangerButton extends StatelessWidget {
  const _SheetDangerButton({
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: PvColors.red.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: PvColors.red),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: PvColors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncPlayHomeSheet extends StatelessWidget {
  const _SyncPlayHomeSheet({required this.playerController});

  final PlayerController playerController;

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (context) {
      // Read all observables here; the deferred body builder is not tracked.
      final bool hasSession = playerController.syncplay.hasSession;
      final String room = playerController.syncplay.syncplayRoom;
      final int rtt = playerController.syncplay.syncplayClientRtt;
      final bool connected = room.isNotEmpty;
      // Lock server selection while connected, even before joining a room.
      final bool connecting = hasSession && !connected;

      return _SyncPlaySheetScaffold(
        title: '一起看',
        description: '和朋友同步看番',
        dangerAction: hasSession
            ? _SheetDangerButton(
                label: connecting ? '取消连接' : '断开连接',
                icon: Icons.logout_rounded,
                onTap: () async {
                  await playerController.exitSyncPlayRoom();
                },
              )
            : null,
        bodyBuilder: (context, compact) {
          if (connected) {
            return _buildConnected(context, room: room, rtt: rtt);
          }
          if (connecting) {
            return _buildConnecting(context);
          }
          return _buildLobby(context, compact: compact);
        },
      );
    });
  }

  Widget _buildConnecting(BuildContext context) {
    return PvGroup(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 14),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
          child: Row(
            children: [
              const SizedBox.square(
                dimension: 20,
                child: LoadingIndicator(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('正在连接', style: PvText.rowTitle(context)),
                    const SizedBox(height: 2),
                    Text(
                      _readEndPoint(),
                      overflow: TextOverflow.ellipsis,
                      style: PvText.rowSub(context).copyWith(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLobby(BuildContext context, {required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PvGroup(
          margin: const EdgeInsets.fromLTRB(0, 0, 0, 14),
          children: [
            PvRow(
              icon: Icons.add_rounded,
              iconColor: PvColors.blue,
              title: '创建房间',
              subtitle: '生成房号，邀请朋友加入',
              showDivider: false,
              onTap: () =>
                  Navigator.of(context).pop(_SyncPlayDestination.create),
            ),
            PvRow(
              icon: Icons.login_rounded,
              iconColor: PvColors.green,
              title: '加入房间',
              subtitle: '输入好友的 8 位房号',
              onTap: () => Navigator.of(context).pop(_SyncPlayDestination.join),
            ),
          ],
        ),
        PvGroup(
          margin: const EdgeInsets.fromLTRB(0, 0, 0, 14),
          children: [
            PvRow(
              icon: Icons.dns_rounded,
              iconColor: PvColors.ink3(context).withValues(alpha: 0.55),
              title: '同步服务器',
              subtitle: _readEndPoint(),
              showDivider: false,
              onTap: () => Navigator.of(context).pop(_SyncPlayDestination.server),
            ),
          ],
        ),
        Text(
          '房间成员需要连同一个服务器才能互相看见',
          style: PvText.rowSub(context).copyWith(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildConnected(
    BuildContext context, {
    required String room,
    required int rtt,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RoomNumberCard(room: room, label: '当前房间', trailing: [
          _CopyChip(value: room),
        ]),
        const SizedBox(height: 12),
        PvGroup(
          margin: const EdgeInsets.fromLTRB(0, 0, 0, 14),
          children: [
            PvRow(
              icon: Icons.network_ping_rounded,
              iconColor: PvColors.green,
              title: '网络延迟',
              value: '$rtt ms',
              trailing: PvRowTrailing.none,
              showDivider: false,
            ),
            PvRow(
              icon: Icons.dns_rounded,
              iconColor: PvColors.ink3(context).withValues(alpha: 0.55),
              title: '同步服务器',
              value: _readEndPoint(),
              trailing: PvRowTrailing.none,
            ),
          ],
        ),
        Text(
          '分享房间号，好友即可加入',
          style: PvText.rowSub(context).copyWith(fontSize: 12),
        ),
      ],
    );
  }
}

class _SyncPlayRoomSheet extends StatefulWidget {
  const _SyncPlayRoomSheet({
    required this.isCreate,
    required this.playerController,
    required this.changeEpisode,
  });

  final bool isCreate;
  final PlayerController playerController;
  final Future<void> Function(int episode, {int currentRoad, int offset})
      changeEpisode;

  @override
  State<_SyncPlayRoomSheet> createState() => _SyncPlayRoomSheetState();
}

class _SyncPlayRoomSheetState extends State<_SyncPlayRoomSheet> {
  static final Random _random = Random();

  static String _generateRoomNumber() => List.generate(
        kSyncPlayRoomNumberLength,
        (_) => _random.nextInt(10),
      ).join();

  static String _generateUserName() {
    const String consonants = 'bcdfghjklmnpqrstvwxyz';
    const String vowels = 'aeiou';
    final int syllables = 3 + _random.nextInt(2);
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < syllables; i++) {
      buffer.write(consonants[_random.nextInt(consonants.length)]);
      buffer.write(vowels[_random.nextInt(vowels.length)]);
    }
    final String name = buffer.toString();
    return name[0].toUpperCase() + name.substring(1);
  }

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _roomController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

  late String _createdRoom = _generateRoomNumber();

  @override
  void initState() {
    super.initState();
    _usernameController.text =
        GStorage.getSetting<String>(SettingsKeys.syncPlayUserName);
    if (_usernameController.text.isEmpty) {
      _usernameController.text = _generateUserName();
    }
  }

  @override
  void dispose() {
    _roomController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final String username = _usernameController.text.trim();
    final String room =
        widget.isCreate ? _createdRoom : _roomController.text.trim();
    GStorage.putSetting<String>(SettingsKeys.syncPlayUserName, username);

    Navigator.of(context).pop();
    widget.playerController
        .createSyncPlayRoom(room, username, widget.changeEpisode);
  }

  @override
  Widget build(BuildContext context) {
    final bool isCreate = widget.isCreate;

    return _SyncPlaySheetScaffold(
      title: isCreate ? '创建房间' : '加入房间',
      description: isCreate ? '把房间号发给朋友' : '输入好友分享的 8 位房号',
      action: _SheetPrimaryButton(
        label: isCreate ? '创建并加入' : '加入房间',
        icon: isCreate
            ? Icons.play_circle_outline_rounded
            : Icons.login_rounded,
        onTap: _submit,
      ),
      bodyBuilder: (context, compact) {
        final Widget lead = isCreate
            ? _RoomNumberCard(
                room: _createdRoom,
                label: '房间号',
                trailing: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        setState(() => _createdRoom = _generateRoomNumber()),
                    child: Tooltip(
                      message: '重新生成',
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Icon(
                          Icons.refresh_rounded,
                          size: 19,
                          color: PvColors.ink2(context),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  _CopyChip(value: _createdRoom),
                ],
              )
            : _buildRoomField(context);

        return Form(
          key: _formKey,
          child: compact
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: lead),
                    const SizedBox(width: 12),
                    Expanded(child: _buildUsernameField(context, compact: true)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    lead,
                    const SizedBox(height: 12),
                    _buildUsernameField(context),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildRoomField(BuildContext context) {
    return TextFormField(
      controller: _roomController,
      autofocus: true,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      style: TextStyle(fontSize: 15, color: PvColors.ink(context)),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      autovalidateMode: AutovalidateMode.onUserInteraction,
      maxLength: kSyncPlayRoomNumberLength,
      buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
          null,
      decoration: _sheetFieldDecoration(
        context,
        hint: '房间号（$kSyncPlayRoomNumberLength 位数字）',
      ),
      validator: (value) {
        final String text = (value ?? '').trim();
        if (text.isEmpty) {
          return '请输入房间号';
        }
        // 房号生成端固定 8 位，校验端曾经接受 6-10 位：输 6 位能提交，
        // 但服务端只认那 8 位，必然连不上。校验必须和生成保持同一个长度。
        if (!RegExp('^[0-9]{$kSyncPlayRoomNumberLength}\$').hasMatch(text)) {
          return '房间号为 $kSyncPlayRoomNumberLength 位数字';
        }
        return null;
      },
    );
  }

  Widget _buildUsernameField(BuildContext context, {bool compact = false}) {
    return TextFormField(
      controller: _usernameController,
      textInputAction: TextInputAction.done,
      style: TextStyle(fontSize: 15, color: PvColors.ink(context)),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: _sheetFieldDecoration(
        context,
        hint: compact ? '昵称' : '昵称（4-12 位英文字母）',
      ),
      validator: (value) {
        final String text = (value ?? '').trim();
        if (text.isEmpty) {
          return '请输入昵称';
        }
        if (!RegExp(r'^[a-zA-Z]{4,12}$').hasMatch(text)) {
          return '昵称为 4-12 位英文字母';
        }
        return null;
      },
      onFieldSubmitted: (_) => _submit(),
    );
  }
}

class _SyncPlayServerSheet extends StatefulWidget {
  const _SyncPlayServerSheet();

  @override
  State<_SyncPlayServerSheet> createState() => _SyncPlayServerSheetState();
}

class _SyncPlayServerSheetState extends State<_SyncPlayServerSheet> {
  static const String _customOption = '自定义服务器';

  final TextEditingController _customEndPointController =
      TextEditingController();

  late String _selectedEndPoint;
  String? _customEndPointError;

  // Request keyboard focus only after an explicit custom-server selection.
  bool _focusCustomEndPoint = false;

  /// 服务器地址 -> 握手耗时，null 表示连不上。
  final Map<String, Duration?> _latency = {};
  bool _isProbing = false;

  @override
  void initState() {
    super.initState();
    final String savedEndPoint = _readEndPoint();
    if (officialSyncPlayEndPoints.contains(savedEndPoint)) {
      _selectedEndPoint = savedEndPoint;
    } else {
      _selectedEndPoint = _customOption;
      _customEndPointController.text = savedEndPoint;
    }
    _probeAll();
  }

  Future<void> _probeAll() async {
    if (_isProbing) return;
    setState(() => _isProbing = true);
    final targets = officialSyncPlayEndPoints.toList();
    if (!officialSyncPlayEndPoints.contains(_readEndPoint())) {
      targets.add(_readEndPoint());
    }
    await Future.wait(targets.map(_probeOne));
    if (!mounted) return;
    setState(() => _isProbing = false);
  }

  Future<void> _probeOne(String endPoint) async {
    final parsed = parseSyncPlayEndPoint(endPoint);
    if (parsed == null) {
      _latency[endPoint] = null;
      return;
    }
    try {
      _latency[endPoint] = await SyncPlayLatencyProbe().measure(
        host: parsed.host,
        port: parsed.port,
        enableTLS: isOfficialSyncPlayEndPoint(parsed),
      );
    } catch (_) {
      _latency[endPoint] = null;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _customEndPointController.dispose();
    super.dispose();
  }

  void _save() {
    String endPoint = _selectedEndPoint;
    if (endPoint == _customOption) {
      endPoint = _customEndPointController.text.trim();
      if (parseSyncPlayEndPoint(endPoint) == null) {
        setState(() => _customEndPointError = '地址格式为 host:port');
        return;
      }
    }
    GStorage.putSetting<String>(SettingsKeys.syncPlayEndPoint, endPoint);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return _SyncPlaySheetScaffold(
      title: '同步服务器',
      description: '房间成员需使用同一服务器',
      action: _SheetPrimaryButton(
        label: '保存',
        icon: Icons.check_rounded,
        onTap: _save,
      ),
      bodyBuilder: (context, compact) {
        final List<String> endPoints = [
          ...officialSyncPlayEndPoints,
          _customOption,
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  _isProbing ? '测速中…' : '点一下实测延迟',
                  style: PvText.rowSub(context).copyWith(fontSize: 12.5),
                ),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _isProbing ? null : _probeAll,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: PvColors.blue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isProbing)
                          const SizedBox.square(
                            dimension: 13,
                            child: LoadingIndicator(),
                          )
                        else
                          const Icon(Icons.network_ping_rounded,
                              size: 13, color: PvColors.blue),
                        const SizedBox(width: 5),
                        Text(
                          _isProbing ? '测速中' : '测速',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: PvColors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            PvGroup(
              margin: EdgeInsets.zero,
              children: [
                for (var i = 0; i < endPoints.length; i++)
                  _EndPointRow(
                    endPoint: endPoints[i],
                    isCustom: endPoints[i] == _customOption,
                    selected: _selectedEndPoint == endPoints[i],
                    latency: _latency[endPoints[i]],
                    probing: _isProbing && !_latency.containsKey(endPoints[i]),
                    showDivider: i > 0,
                    onTap: () => setState(() {
                      _selectedEndPoint = endPoints[i];
                      _customEndPointError = null;
                      _focusCustomEndPoint = endPoints[i] == _customOption;
                    }),
                  ),
              ],
            ),
            if (_selectedEndPoint == _customOption) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customEndPointController,
                autofocus: _focusCustomEndPoint,
                keyboardType: TextInputType.url,
                autocorrect: false,
                style: TextStyle(fontSize: 15, color: PvColors.ink(context)),
                decoration: _sheetFieldDecoration(
                  context,
                  hint: 'example.com:8996',
                  error: _customEndPointError,
                ),
                onChanged: (_) {
                  if (_customEndPointError != null) {
                    setState(() => _customEndPointError = null);
                  }
                },
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 服务器列表里的一行：勾选圈 + 地址 + 实测延迟。
class _EndPointRow extends StatelessWidget {
  const _EndPointRow({
    required this.endPoint,
    required this.isCustom,
    required this.selected,
    required this.latency,
    required this.probing,
    required this.showDivider,
    required this.onTap,
  });

  final String endPoint;
  final bool isCustom;
  final bool selected;
  final Duration? latency;
  final bool probing;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String latencyText;
    final Color latencyColor;
    if (probing) {
      latencyText = '…';
      latencyColor = PvColors.ink3(context);
    } else if (latency == null) {
      latencyText = '未测';
      latencyColor = PvColors.ink3(context);
    } else {
      final int ms = latency!.inMilliseconds;
      latencyText = '$ms ms';
      latencyColor = ms < 120
          ? PvColors.green
          : (ms < 300 ? const Color(0xFFE0912F) : PvColors.red);
    }

    final Widget body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              size: 19,
              color: selected ? PvColors.blue : PvColors.chev(context),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                endPoint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PvText.rowTitle(context).copyWith(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? PvColors.blue : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              latencyText,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: latencyColor,
              ),
            ),
            if (isCustom) ...[
              const SizedBox(width: 6),
              Icon(Icons.edit_rounded, size: 14, color: PvColors.ink3(context)),
            ],
          ],
        ),
      ),
    );

    final Widget tappable = InkWell(onTap: onTap, child: body);
    if (!showDivider) return tappable;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 0.8,
          margin: const EdgeInsets.only(left: 45),
          color: PvColors.hair(context),
        ),
        tappable,
      ],
    );
  }
}

/// 房号卡：`4601 5081` 大字 + 右侧若干动作。
class _RoomNumberCard extends StatelessWidget {
  const _RoomNumberCard({
    required this.room,
    required this.label,
    required this.trailing,
  });

  final String room;
  final String label;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final String pretty =
        room.length == 8 ? '${room.substring(0, 4)} ${room.substring(4)}' : room;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 13),
      decoration: BoxDecoration(
        color: PvColors.card(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: PvText.count(context).copyWith(fontSize: 12)),
          const SizedBox(height: 3),
          Row(
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    pretty,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: PvColors.ink(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ...trailing,
            ],
          ),
        ],
      ),
    );
  }
}

/// 「复制」小胶囊，点完变「已复制」，两秒后自己变回来。
class _CopyChip extends StatefulWidget {
  const _CopyChip({required this.value});

  final String value;

  @override
  State<_CopyChip> createState() => _CopyChipState();
}

class _CopyChipState extends State<_CopyChip> {
  bool _copied = false;

  @override
  void didUpdateWidget(_CopyChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _copied = false;
    }
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.value));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _copy,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: PvColors.blue.withValues(alpha: _copied ? 0.20 : 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _copied ? Icons.check_rounded : Icons.copy_rounded,
              size: 12,
              color: PvColors.blue,
            ),
            const SizedBox(width: 4),
            Text(
              _copied ? '已复制' : '复制',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: PvColors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
