import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bridge_providers.dart';
import '../../app/providers.dart';
import '../../bridges/bridge_config.dart';
import '../../bridges/bridge_protocol.dart';
import '../../core/proto/mesh.dart';
import '../../core/radio/radio_session.dart';
import '../../l10n/l10n.dart';
import '../../ui/kit/kit.dart';

class BridgesPage extends ConsumerWidget {
  const BridgesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(bridgeConfigProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.bridgesTitle)),
      body: config.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(context.l10n.bridgeSaveFailed)),
        data: (value) => _BridgeForm(value),
      ),
    );
  }
}

class _BridgeForm extends ConsumerStatefulWidget {
  const _BridgeForm(this.config);
  final BridgeConfig config;

  @override
  ConsumerState<_BridgeForm> createState() => _BridgeFormState();
}

class _BridgeFormState extends ConsumerState<_BridgeForm> {
  final _form = GlobalKey<FormState>();
  final _endpoint = TextEditingController();
  final _arguments = TextEditingController();
  final _secret = TextEditingController();
  late BridgeConfig _saved;
  late BridgeTransport _transport;
  late int _node;
  late bool _direct;
  late bool _sendDirect;
  late bool _sendChannels;
  late Map<String, BridgeChannelMode> _channels;
  bool _dirty = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final config = _saved = widget.config;
    _transport = config.transport;
    _endpoint.text = config.endpoint;
    _arguments.text = config.arguments.join('\n');
    _node = config.node;
    _direct = config.direct;
    _sendDirect = config.sendDirect;
    _sendChannels = config.sendChannels;
    _channels = Map.of(config.channels);
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _arguments.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _edit([VoidCallback? change]) => setState(() {
    change?.call();
    _dirty = true;
  });

  Future<void> _pickProcess() async {
    await _run(() async {
      final result = await FilePicker.pickFiles();
      final path = result.singleOrNull?.path;
      if (mounted && path != null) _edit(() => _endpoint.text = path);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      final s = context.l10n;
      final description = switch (error) {
        BridgeError(message: 'Enter a connection token') =>
          s.bridgeTokenRequired,
        _ => s.bridgeSaveFailed,
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(description)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      final config = await ref
          .read(bridgeControllerProvider)
          .save(
            BridgeConfig(
              transport: _transport,
              endpoint: _endpoint.text.trim(),
              arguments: _transport == BridgeTransport.process
                  ? _arguments.text
                        .split('\n')
                        .where((value) => value.isNotEmpty)
                        .toList()
                  : const [],
              node: _node,
              direct: _direct,
              sendDirect: _sendDirect,
              sendChannels: _sendChannels && _channels.isNotEmpty,
              channels: _channels,
            ),
            _transport == BridgeTransport.process ? '' : _secret.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _saved = config;
        _secret.clear();
        _dirty = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final controller = ref.watch(bridgeControllerProvider);
    final activeNode = ref.watch(activeNodeDbProvider);
    final channels = ref.watch(bridgeChannelsProvider);
    final readyNode = ref.watch(
      radioProvider.select(
        (radio) => radio.state == RadioState.ready ? radio.myNodeNum : null,
      ),
    );
    final running = controller.state == BridgeState.running;
    final connecting = controller.state == BridgeState.connecting;
    final status = switch (controller.state) {
      BridgeState.stopped => s.bridgeStopped,
      BridgeState.connecting => s.bridgeConnecting,
      BridgeState.failed => s.bridgeDisconnected,
      BridgeState.running when readyNode != _saved.node =>
        s.bridgeWaitingForNode,
      BridgeState.running => s.bridgeConnected,
    };
    final editable = !_busy && !connecting;
    final showChannels = _node != 0 && _node == activeNode;
    final storedSecret =
        _saved.id.isNotEmpty &&
        _transport == BridgeTransport.http &&
        _saved.transport == BridgeTransport.http &&
        _saved.endpoint == _endpoint.text.trim();

    return Form(
      key: _form,
      child: ListView(
        padding: pagePadding(context),
        children: [
          SectionCard(
            children: [
              ListTile(
                leading: Icon(running ? Icons.link : Icons.link_off),
                title: Text(status),
                subtitle: controller.detail == null
                    ? null
                    : Text(_statusDetail(s, controller.detail!)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: running || connecting
                          ? controller.stop
                          : !_dirty &&
                                !_busy &&
                                _saved.id.isNotEmpty &&
                                _saved.node != 0
                          ? () => controller.start(_saved)
                          : null,
                      child: Text(
                        running || connecting ? s.bridgeStop : s.bridgeStart,
                      ),
                    ),
                    OutlinedButton(
                      onPressed: editable && _dirty && _node != 0
                          ? _save
                          : null,
                      child: Text(s.bridgeSave),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SectionCard(
            title: s.bridgeConnection,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<BridgeTransport>(
                      initialValue: _transport,
                      decoration: InputDecoration(labelText: s.bridgeType),
                      items: [
                        DropdownMenuItem(
                          value: BridgeTransport.process,
                          child: Text(s.bridgeProcess),
                        ),
                        DropdownMenuItem(
                          value: BridgeTransport.http,
                          child: Text(s.bridgeHttp),
                        ),
                      ],
                      onChanged: !editable
                          ? null
                          : (value) {
                              if (value == null || value == _transport) return;
                              _edit(() {
                                _transport = value;
                                _endpoint.clear();
                                _arguments.clear();
                                _secret.clear();
                              });
                            },
                    ),
                    TextFormField(
                      controller: _endpoint,
                      enabled: editable,
                      onChanged: (_) => _edit(),
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: _transport == BridgeTransport.process
                            ? s.bridgeExecutable
                            : s.bridgeAddress,
                        hintText: _transport == BridgeTransport.http
                            ? 'http://127.0.0.1:8765'
                            : null,
                        suffixIcon: _transport == BridgeTransport.process
                            ? IconButton(
                                tooltip: s.bridgeExecutable,
                                onPressed: editable ? _pickProcess : null,
                                icon: const Icon(Icons.folder_open),
                              )
                            : null,
                      ),
                      validator: (value) {
                        final input = value?.trim() ?? '';
                        if (_transport == BridgeTransport.http) {
                          return bridgeHttpEndpoint(input) == null
                              ? s.bridgeInvalidAddress
                              : null;
                        }
                        return input.isEmpty ||
                                !File(input).isAbsolute ||
                                (Platform.isWindows &&
                                    !input.toLowerCase().endsWith('.exe'))
                            ? s.bridgeInvalidExecutable
                            : null;
                      },
                    ),
                    if (_transport == BridgeTransport.process)
                      TextFormField(
                        controller: _arguments,
                        enabled: editable,
                        minLines: 2,
                        maxLines: 5,
                        autocorrect: false,
                        onChanged: (_) => _edit(),
                        decoration: InputDecoration(
                          labelText: s.bridgeArguments,
                        ),
                      )
                    else
                      TextFormField(
                        key: ValueKey(_transport),
                        controller: _secret,
                        enabled: editable,
                        obscureText: true,
                        onChanged: (_) => _edit(),
                        decoration: InputDecoration(
                          labelText: s.bridgeHttpToken,
                          hintText: storedSecret ? s.bridgeTokenSaved : null,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          SectionCard(
            title: s.bridgeMeshAccess,
            children: [
              ListTile(
                title: Text(
                  _node == 0
                      ? s.bridgeNoNode
                      : s.bridgeNode(nodeIdString(_node)),
                ),
                subtitle: Text(s.bridgeNodeHelp),
                trailing: activeNode != 0 && activeNode != _node
                    ? TextButton(
                        onPressed: editable
                            ? () => _edit(() {
                                _node = activeNode;
                                _channels.clear();
                              })
                            : null,
                        child: Text(
                          s.bridgeSelectNode(nodeIdString(activeNode)),
                        ),
                      )
                    : null,
              ),
              SwitchListTile(
                title: Text(s.bridgeReceiveDirect),
                value: _direct,
                onChanged: editable
                    ? (value) => _edit(() => _direct = value)
                    : null,
              ),
              SwitchListTile(
                title: Text(s.bridgeSendDirect),
                value: _sendDirect,
                onChanged: editable
                    ? (value) => _edit(() => _sendDirect = value)
                    : null,
              ),
              SwitchListTile(
                title: Text(s.bridgeSendChannels),
                value: _sendChannels && _channels.isNotEmpty,
                onChanged: editable && _channels.isNotEmpty
                    ? (value) => _edit(() => _sendChannels = value)
                    : null,
              ),
              if (showChannels)
                ...channels.when(
                  loading: () => [const LinearProgressIndicator()],
                  error: (_, _) => [ListTile(title: Text(s.bridgeSaveFailed))],
                  data: (values) => [
                    for (final channel in values)
                      ListTile(
                        title: Text('#${channel.title}'),
                        trailing: DropdownButton<BridgeChannelMode?>(
                          value: _channels[channel.fingerprint],
                          hint: Text(s.bridgeChannelOff),
                          items: [
                            DropdownMenuItem(
                              value: null,
                              child: Text(s.bridgeChannelOff),
                            ),
                            DropdownMenuItem(
                              value: BridgeChannelMode.mentions,
                              child: Text(s.bridgeChannelMentions),
                            ),
                            DropdownMenuItem(
                              value: BridgeChannelMode.all,
                              child: Text(s.bridgeChannelAll),
                            ),
                          ],
                          onChanged: !editable
                              ? null
                              : (mode) => _edit(() {
                                  if (mode == null) {
                                    _channels.remove(channel.fingerprint);
                                  } else {
                                    _channels[channel.fingerprint] = mode;
                                  }
                                }),
                        ),
                      ),
                    if (values.isEmpty)
                      ListTile(title: Text(s.bridgeNoChannels)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _statusDetail(AppLocalizations s, String detail) =>
      switch (detail) {
        'Connection to the module closed' => s.bridgeModuleClosed,
        'Incompatible bridge API' => s.bridgeIncompatible,
        'Save a connection token first' => s.bridgeTokenRequired,
        _ => s.bridgeModuleConnectionFailed,
      };
}
