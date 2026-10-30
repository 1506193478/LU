import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/bean/settings/settings_detail_scaffold.dart';
import 'package:XL/bean/widget/clay.dart';
import 'package:XL/bean/widget/clay_neu.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/emby/emby_widgets.dart';
import 'package:XL/request/clients/emby_client.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/services/logging/logger.dart';

/// 服务器列表：切换、编辑、删除。
class EmbyServerPage extends StatelessWidget {
  const EmbyServerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = EmbyService.instance;
    return SettingsDetailScaffold(
      title: const Text('Emby 服务器'),
      actions: [
        IconButton(
          tooltip: '添加服务器',
          onPressed: () => _edit(context, null),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      body: ValueListenableBuilder<int>(
        valueListenable: service.revision,
        builder: (context, _, _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final service = EmbyService.instance;
    final servers = service.servers;
    final active = service.activeServer;
    if (servers.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const EmbyIntro(
                  icon: Icons.dns_rounded,
                  title: '还没有服务器',
                  description: '添加一个 Emby 或 Jellyfin 服务器，就能浏览上面的媒体库。',
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => _edit(context, null),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('添加服务器'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        for (final server in servers)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ServerTile(
              server: server,
              isActive: active?.id == server.id,
              onTap: () => _edit(context, server),
              onActivate: () async {
                await service.setActive(server.id);
                if (context.mounted) Navigator.of(context).maybePop();
              },
              onDelete: () => _delete(context, server),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _edit(context, null),
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加服务器'),
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, EmbyServer? server) async {
    await context.pushNamed('/emby/servers/edit', arguments: server);
  }

  Future<void> _delete(BuildContext context, EmbyServer server) async {
    final confirmed = await ClayDialog.confirm(
      context,
      title: '删除这台服务器？',
      message: '只会删掉 LU 里保存的地址和登录凭据，不影响 Emby 服务端本身。',
      icon: Icons.delete_outline_rounded,
      confirmLabel: '删除',
      destructive: true,
    );
    if (confirmed != true) return;
    await EmbyService.instance.remove(server.id);
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.server,
    required this.isActive,
    required this.onTap,
    required this.onActivate,
    required this.onDelete,
  });

  final EmbyServer server;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onActivate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(
            isActive ? Icons.check_circle_rounded : Icons.dns_outlined,
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  server.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${server.userName} · ${server.url}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              if (value == 'activate') onActivate();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => [
              if (!isActive)
                const PopupMenuItem(value: 'activate', child: Text('设为当前服务器')),
              const PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
    );

    if (isNeuLayout(context)) {
      return NeuSurface(radius: 22, onTap: onTap, child: content);
    }
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// 新增 / 编辑服务器。保存前先真的登一次，密码错了当场就知道。
class EmbyServerEditPage extends StatefulWidget {
  const EmbyServerEditPage({super.key, this.server});

  /// null 表示新增。
  final EmbyServer? server;

  @override
  State<EmbyServerEditPage> createState() => _EmbyServerEditPageState();
}

class _EmbyServerEditPageState extends State<EmbyServerEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _allowBadCertificate = false;
  bool _passwordVisible = false;
  bool _busy = false;
  bool _failed = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final server = widget.server;
    if (server != null) {
      _url.text = server.url;
      _username.text = server.userName;
      _name.text = server.name;
      _allowBadCertificate = server.allowBadCertificate;
      // 已保存的 Token 不复填到密码框：用户改地址才需要重填密码，
      // 不改的话保存时直接沿用旧 Token。
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _failed = false;
      _message = '正在连接…';
    });

    final existing = widget.server;
    final normalized = normalizeEmbyUrl(_url.text);
    try {
      // 地址没变、密码没填，说明用户只是想改备注或证书开关，沿用旧 Token。
      final bool reuseToken = existing != null &&
          existing.url == normalized &&
          _password.text.isEmpty;
      if (reuseToken) {
        await _persist(
          existing.copyWith(
            name: _name.text.trim().isEmpty ? existing.name : _name.text.trim(),
            allowBadCertificate: _allowBadCertificate,
          ),
        );
        return;
      }

      final client = EmbyClient(
        serverUrl: normalized,
        allowBadCertificate: _allowBadCertificate,
        deviceId: EmbyService.instance.deviceId,
      );
      final EmbyAuthResult auth;
      try {
        auth = await client.authenticate(
          username: _username.text.trim(),
          password: _password.text,
        );
      } finally {
        client.close();
      }

      await _persist(
        EmbyServer(
          id: existing?.id ?? EmbyService.newServerId(),
          name: _name.text.trim().isEmpty
              ? auth.serverName
              : _name.text.trim(),
          url: normalized,
          userId: auth.userId,
          userName: auth.userName,
          accessToken: auth.accessToken,
          allowBadCertificate: _allowBadCertificate,
        ),
      );
    } catch (e) {
      KazumiLogger().w('Emby: server setup failed', error: e);
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
          _message = embyErrorMessage(e);
        });
      }
    }
  }

  Future<void> _persist(EmbyServer server) async {
    await EmbyService.instance.upsert(server);
    await EmbyService.instance.setActive(server.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = false;
      _message = '连接成功';
    });
    // 让用户看到"连接成功"再退回列表。
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isNew = widget.server == null;
    return PopScope(
      canPop: !_busy,
      child: SettingsDetailScaffold(
        title: Text(isNew ? '添加服务器' : '编辑服务器'),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Form(
                    key: _formKey,
                    onChanged: () {
                      if (_message != null && !_busy) {
                        setState(() => _message = null);
                      }
                    },
                    child: NeuSurface(
                      radius: NeuRadius.card,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        spacing: 18,
                        children: [
                          TextFormField(
                            controller: _url,
                            enabled: !_busy,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: '服务器地址',
                              hintText: 'http://192.168.1.10:8096',
                              border: OutlineInputBorder(),
                              errorMaxLines: 3,
                            ),
                            validator: (value) {
                              final normalized =
                                  normalizeEmbyUrl(value ?? '');
                              if (normalized.isEmpty) {
                                return '请输入完整地址，例如 http://192.168.1.10:8096';
                              }
                              return null;
                            },
                          ),
                          TextFormField(
                            controller: _username,
                            enabled: !_busy,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: '用户名',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty)
                                    ? '请填用户名'
                                    : null,
                          ),
                          TextFormField(
                            controller: _password,
                            enabled: !_busy,
                            obscureText: !_passwordVisible,
                            autocorrect: false,
                            enableSuggestions: false,
                            onFieldSubmitted: (_) => _save(),
                            decoration: InputDecoration(
                              labelText: '密码',
                              helperText: isNew ? null : '留空则沿用已保存的登录凭据',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                tooltip:
                                    _passwordVisible ? '隐藏密码' : '显示密码',
                                onPressed: () => setState(
                                    () => _passwordVisible = !_passwordVisible),
                                icon: Icon(_passwordVisible
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded),
                              ),
                            ),
                            validator: (value) {
                              if (isNew &&
                                  (value == null || value.isEmpty)) {
                                return '请填密码';
                              }
                              return null;
                            },
                          ),
                          TextFormField(
                            controller: _name,
                            enabled: !_busy,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: '备注名（可留空）',
                              helperText: '留空就用服务器自己的名字',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          SwitchListTile(
                            value: _allowBadCertificate,
                            onChanged: _busy
                                ? null
                                : (value) => setState(
                                    () => _allowBadCertificate = value),
                            contentPadding: EdgeInsets.zero,
                            title: const Text('允许自签证书'),
                            subtitle: const Text('局域网自建服务器常用自签 HTTPS，开启后才能连上'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.login_rounded),
                    label: Text(_busy ? '正在连接…' : '保存并登录'),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _failed
                            ? theme.colorScheme.errorContainer
                            : theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _failed
                                ? Icons.error_outline_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 20,
                            color: _failed
                                ? theme.colorScheme.onErrorContainer
                                : theme.colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _message!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: _failed
                                    ? theme.colorScheme.onErrorContainer
                                    : theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
