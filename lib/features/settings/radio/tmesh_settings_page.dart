import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meshex/l10n/l10n.dart';
import 'package:protobuf/protobuf.dart' show ProtobufEnum;

import '../../../app/link_badge.dart';
import '../../../app/providers.dart';
import '../../../app/settings_providers.dart';
import '../../../app/toasts.dart';
import '../../../core/proto/tmesh/feature_flags.pb.dart' as tmesh;
import '../../../core/radio/tmesh_settings.dart';
import '../../../data/database.dart';
import '../../../data/mentions.dart';
import '../../../ui/kit/kit.dart';

class TmeshSettingsPage extends ConsumerWidget {
  const TmeshSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final probe = ref.watch(tmeshProbeProvider);
    final client = probe.asData?.value;
    return Scaffold(
      appBar: AppBar(title: const Text('TMesh'), actions: const [LinkBadge()]),
      body: client != null
          ? _Editor(key: ObjectKey(client), client: client)
          : Center(
              child: probe.isLoading
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: pagePadding(context),
                      child: Text(context.l10n.tmeshUnavailable),
                    ),
            ),
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({super.key, required this.client});

  final TmeshSettings client;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  tmesh.FeatureFlagsConfig? _saved;
  tmesh.FeatureFlagsConfig? _draft;
  final _forceRelay = TextEditingController();
  final _favoriteRelay = TextEditingController();
  int _formVersion = 0;
  bool _busy = true;
  TmeshError? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _forceRelay.dispose();
    _favoriteRelay.dispose();
    super.dispose();
  }

  tmesh.FeatureFlagsConfig get _baseline =>
      _saved ?? tmesh.FeatureFlagsConfig.getDefault();

  void _apply(tmesh.FeatureFlagsConfig? config) {
    _saved = config;
    _draft = _baseline.deepCopy();
    _forceRelay.text = _relayHex(_baseline.forceNextHopRelay);
    _favoriteRelay.text = _relayHex(_baseline.favoriteRouterRelay);
    _formVersion++;
  }

  Future<void> _load() => _run(widget.client.read);

  Future<void> _run(
    Future<tmesh.FeatureFlagsConfig?> Function() operation, {
    bool write = false,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final config = await operation();
      if (!mounted) return;
      setState(() => _apply(config));
      if (write) {
        toasts.show(context.l10n.saved_f0dff5, kind: ToastKind.success);
      }
    } on TmeshError catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(tmesh.FeatureFlagsConfig edited) async {
    if (_busy || _error != null) return;
    final baseline = _baseline;
    final hadConfig = _saved != null;
    await _run(
      () => widget.client.save(
        hadConfig: hadConfig,
        edit: (fresh) => _mergeEdits(fresh, baseline, edited),
      ),
      write: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.l10n;
    final draft = _draft;
    final error = _error;
    final editable = !_busy && error == null;
    final nodes = ref.watch(nodesProvider).value ?? const <Node>[];
    final forceRelay = _relayValue(
      _forceRelay.text,
      draft?.forceNextHopMode.value,
    );
    final favoriteRelay = _relayValue(
      _favoriteRelay.text,
      draft?.favoriteRouterMode.value,
    );
    final edited = draft == null || forceRelay == null || favoriteRelay == null
        ? null
        : (draft.deepCopy()
            ..forceNextHopRelay = forceRelay
            ..favoriteRouterRelay = favoriteRelay);
    final canSave =
        editable && edited != null && edited.values != _baseline.values;
    return ListView(
      padding: pagePadding(context),
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (error != null) ...[
          WarningNote(_errorText(strings, error)),
          TextButton(
            onPressed: _busy ? null : _load,
            child: Text(strings.tmeshReadAgain),
          ),
        ],
        if (draft != null) ...[
          KeyedSubtree(
            key: ValueKey(_formVersion),
            child: _fields(
              strings,
              draft,
              editable,
              nodes,
              forceRelay,
              favoriteRelay,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Tokens.s16),
            child: FilledButton(
              onPressed: canSave ? () => _save(edited) : null,
              child: Text(strings.save_486405),
            ),
          ),
        ],
      ],
    );
  }

  Widget _fields(
    AppLocalizations strings,
    tmesh.FeatureFlagsConfig draft,
    bool editable,
    List<Node> nodes,
    int? forceRelay,
    int? favoriteRelay,
  ) => Column(
    children: [
      SectionCard(
        title: strings.tmeshRouting,
        footer: strings.tmeshRoutingHelp,
        children: [
          _choice<tmesh.FeatureFlagsConfig_RestrictedRoutingMode>(
            label: strings.tmeshRestrictedRouting,
            value: draft.restrictedRoutingMode,
            values: tmesh.FeatureFlagsConfig_RestrictedRoutingMode.values,
            labels: [
              strings.tmeshStandardPorts,
              strings.tmeshTextAdmin,
              strings.tmeshTextAdminRouting,
              strings.tmeshTextAdminRoutingTrace,
              strings.tmeshTextNodeInfoAdminRouting,
              strings.tmeshTextNodeInfoAdminRoutingTrace,
            ],
            onChanged: editable
                ? (value) => setState(() => draft.restrictedRoutingMode = value)
                : null,
          ),
          SwitchListTile(
            title: Text(strings.tmeshBlockPrivateText),
            subtitle: Text(strings.tmeshPrivateTextHelp),
            value: draft.restrictedRoutingDisallowsPrivateText,
            onChanged: editable
                ? (value) => setState(
                    () => draft.restrictedRoutingDisallowsPrivateText = value,
                  )
                : null,
          ),
        ],
      ),
      SectionCard(
        title: strings.tmeshHopsSection,
        children: [
          _choice<tmesh.FeatureFlagsConfig_HopDecrementMode>(
            label: strings.tmeshHopDecrement,
            value: draft.hopDecrementMode,
            help: [
              strings.tmeshHopStandardHelp,
              strings.tmeshHopFavoriteHelp,
              strings.tmeshHopFirstHelp,
            ][draft.hopDecrementMode.value],
            values: tmesh.FeatureFlagsConfig_HopDecrementMode.values,
            labels: [
              strings.tmeshStandard,
              strings.tmeshPreserveAfterFavorite,
              strings.tmeshDecrementFirstHop,
            ],
            onChanged: editable
                ? (value) => setState(() => draft.hopDecrementMode = value)
                : null,
          ),
        ],
      ),
      SectionCard(
        title: strings.tmeshForceNextHop,
        children: [
          _choice<tmesh.FeatureFlagsConfig_ForceNextHopMode>(
            label: strings.tmeshMode,
            value: draft.forceNextHopMode,
            help: [
              strings.tmeshForceDisabledHelp,
              strings.tmeshForceLocalHelp,
              strings.tmeshForceRelayedHelp,
              strings.tmeshForceStrictHelp,
            ][draft.forceNextHopMode.value],
            values: tmesh.FeatureFlagsConfig_ForceNextHopMode.values,
            labels: [
              strings.tmeshDisabled,
              strings.tmeshLocalWithFlooding,
              strings.tmeshLocalAndRelayedWithFlooding,
              strings.tmeshAllWithoutFlooding,
            ],
            onChanged: editable
                ? (value) => setState(() => draft.forceNextHopMode = value)
                : null,
          ),
          _relayField(
            controller: _forceRelay,
            relay: forceRelay,
            nodes: nodes,
            requiredByte: draft.forceNextHopMode.value != 0,
            enabled: editable,
          ),
        ],
      ),
      SectionCard(
        title: strings.tmeshFavoriteRouter,
        children: [
          _choice<tmesh.FeatureFlagsConfig_FavoriteRouterMode>(
            label: strings.tmeshMode,
            value: draft.favoriteRouterMode,
            help: [
              strings.tmeshFavoriteDisabledHelp,
              strings.tmeshFavoriteHopsHelp,
              strings.tmeshFavoriteRelayHelp,
            ][draft.favoriteRouterMode.value],
            values: tmesh.FeatureFlagsConfig_FavoriteRouterMode.values,
            labels: [
              strings.tmeshDisabled,
              strings.tmeshPreserveHops,
              strings.tmeshPreserveHopsAndRelay,
            ],
            onChanged: editable
                ? (value) => setState(() => draft.favoriteRouterMode = value)
                : null,
          ),
          _relayField(
            controller: _favoriteRelay,
            relay: favoriteRelay,
            nodes: nodes,
            requiredByte: draft.favoriteRouterMode.value != 0,
            enabled: editable,
          ),
        ],
      ),
    ],
  );

  Widget _relayField({
    required TextEditingController controller,
    required int? relay,
    required List<Node> nodes,
    required bool requiredByte,
    required bool enabled,
  }) {
    final strings = context.l10n;
    final multipleMatches =
        relay != null &&
        relay != 0 &&
        nodes.where((node) => _relayByte(node) == relay).take(2).length > 1;
    return Padding(
      padding: const EdgeInsets.all(Tokens.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Focus(
            onFocusChange: (focused) {
              if (focused || !mounted) return;
              final value = _relayValue(controller.text, 0);
              if (value != null && controller.text != _relayHex(value)) {
                controller.text = _relayHex(value);
              }
            },
            child: TextFormField(
              controller: controller,
              enabled: enabled,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: strings.tmeshRelay,
                helperText: strings.tmeshRelayDescription,
                helperMaxLines: 3,
                errorMaxLines: 2,
                errorText: relay != null
                    ? null
                    : requiredByte
                    ? strings.tmeshRelayRequired
                    : strings.tmeshRelayRange,
                suffixIcon: IconButton(
                  tooltip: strings.tmeshSelectNode,
                  icon: const Icon(Icons.search),
                  onPressed: enabled
                      ? () => _pickRelay(controller, nodes)
                      : null,
                ),
              ),
            ),
          ),
          if (multipleMatches) WarningNote(strings.tmeshRelayCollision),
        ],
      ),
    );
  }

  Future<void> _pickRelay(
    TextEditingController controller,
    List<Node> nodes,
  ) async {
    final candidates = nodes.where(
      (node) => node.num != widget.client.nodeNum && _relayByte(node) != 0,
    );
    final relay = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RelayPicker(nodes: candidates),
    );
    if (!mounted || relay == null || _busy || _error != null) return;
    setState(() => controller.text = _relayHex(relay));
  }

  Widget _choice<T extends ProtobufEnum>({
    required String label,
    required T value,
    required List<T> values,
    required List<String> labels,
    required ValueChanged<T>? onChanged,
    String? help,
  }) => Padding(
    padding: const EdgeInsets.all(Tokens.s16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<T>(
          initialValue: value,
          decoration: InputDecoration(labelText: label),
          isExpanded: true,
          itemHeight: null,
          items: [
            for (var i = 0; i < values.length; i++)
              DropdownMenuItem(
                value: values[i],
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: kMinInteractiveDimension,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(labels[i]),
                  ),
                ),
              ),
          ],
          onChanged: onChanged == null ? null : (value) => onChanged(value!),
        ),
        if (help != null)
          Padding(
            padding: const EdgeInsets.only(top: Tokens.s8),
            child: Text(
              help,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    ),
  );
}

class _RelayPicker extends StatefulWidget {
  const _RelayPicker({required this.nodes});

  final Iterable<Node> nodes;

  @override
  State<_RelayPicker> createState() => _RelayPickerState();
}

class _RelayPickerState extends State<_RelayPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final strings = context.l10n;
    final nodes = NodeMentions.candidates(widget.nodes, _query);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: 0.75,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(Tokens.s16),
                child: TextField(
                  decoration: InputDecoration(
                    labelText: strings.tmeshSelectNode,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (query) =>
                      setState(() => _query = query.trim().toLowerCase()),
                ),
              ),
              Expanded(
                child: nodes.isEmpty
                    ? Center(child: Text(strings.noResultsFound_1e1b70))
                    : ListView.builder(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: nodes.length,
                        itemBuilder: (context, index) {
                          final node = nodes[index];
                          final id = NodeMentions.nodeId(node.num);
                          final shortName = node.shortName.trim();
                          return ListTile(
                            title: Text(
                              NodeMentions.insertion(node, 'longName'),
                            ),
                            subtitle: Text(
                              shortName.isEmpty ? id : '$shortName · $id',
                            ),
                            trailing: Text(_relayHex(_relayByte(node))),
                            onTap: () =>
                                Navigator.pop(context, _relayByte(node)),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

int _relayByte(Node node) => node.num & 0xff;

String _relayHex(int relay) =>
    '0x${relay.toRadixString(16).padLeft(2, '0').toUpperCase()}';

int? _relayValue(String text, int? mode) {
  final value = int.tryParse(text.trim());
  final min = mode == null || mode == 0 ? 0 : 1;
  return value != null && value >= min && value <= 255 ? value : null;
}

void _mergeEdits(
  tmesh.FeatureFlagsConfig fresh,
  tmesh.FeatureFlagsConfig saved,
  tmesh.FeatureFlagsConfig edited,
) {
  if (saved.restrictedRoutingMode != edited.restrictedRoutingMode) {
    fresh.restrictedRoutingMode = edited.restrictedRoutingMode;
  }
  if (saved.restrictedRoutingDisallowsPrivateText !=
      edited.restrictedRoutingDisallowsPrivateText) {
    fresh.restrictedRoutingDisallowsPrivateText =
        edited.restrictedRoutingDisallowsPrivateText;
  }
  if (saved.hopDecrementMode != edited.hopDecrementMode) {
    fresh.hopDecrementMode = edited.hopDecrementMode;
  }
  if (saved.forceNextHopMode != edited.forceNextHopMode) {
    fresh.forceNextHopMode = edited.forceNextHopMode;
  }
  if (saved.forceNextHopRelay != edited.forceNextHopRelay) {
    fresh.forceNextHopRelay = edited.forceNextHopRelay;
  }
  if (saved.favoriteRouterMode != edited.favoriteRouterMode) {
    fresh.favoriteRouterMode = edited.favoriteRouterMode;
  }
  if (saved.favoriteRouterRelay != edited.favoriteRouterRelay) {
    fresh.favoriteRouterRelay = edited.favoriteRouterRelay;
  }
}

String _errorText(AppLocalizations strings, TmeshError error) =>
    switch (error) {
      TmeshError.connectionChanged => strings.tmeshConnectionChanged,
      TmeshError.noResponse => strings.tmeshNoResponse,
      TmeshError.sendRejected => strings.tmeshSendRejected,
      TmeshError.invalidConfig => strings.tmeshInvalidConfig,
      TmeshError.storage => strings.tmeshStorageError,
      TmeshError.configChanged => strings.tmeshConfigChanged,
      TmeshError.writeInProgress => strings.tmeshWriteInProgress,
      TmeshError.unverified => strings.tmeshUnverified,
    };
