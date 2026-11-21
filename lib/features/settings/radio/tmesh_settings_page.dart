import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meshex/l10n/l10n.dart';
import 'package:protobuf/protobuf.dart' show ProtobufEnum;

import '../../../app/link_badge.dart';
import '../../../app/settings_providers.dart';
import '../../../app/toasts.dart';
import '../../../core/proto/tmesh/feature_flags.pb.dart' as tmesh;
import '../../../core/radio/tmesh_settings.dart';
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

class _Editor extends StatefulWidget {
  const _Editor({super.key, required this.client});

  final TmeshSettings client;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  tmesh.FeatureFlagsConfig? _saved;
  tmesh.FeatureFlagsConfig? _draft;
  String _forceRelay = '0';
  String _favoriteRelay = '0';
  int _formVersion = 0;
  bool _busy = true;
  TmeshError? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _setDraft(tmesh.FeatureFlagsConfig? config) {
    _draft = config?.deepCopy();
    _forceRelay = (config?.forceNextHopRelay ?? 0).toString();
    _favoriteRelay = (config?.favoriteRouterRelay ?? 0).toString();
    _formVersion++;
  }

  void _apply(tmesh.FeatureFlagsConfig? config) {
    _saved = config;
    _setDraft(config);
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
    final saved = _saved;
    await _run(
      () => widget.client.save(
        initialize: saved == null,
        edit: (fresh) => _mergeEdits(fresh, saved, edited),
      ),
      write: true,
    );
  }

  Future<void> _clear() async {
    final strings = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.tmeshClearTitle),
        content: Text(strings.tmeshClearDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.cancel_0ec753),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings.tmeshClear),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _busy || _error != null) return;
    await _run(() async {
      await widget.client.clear();
      return null;
    }, write: true);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.l10n;
    final draft = _draft;
    final error = _error;
    final editable = !_busy && error == null;
    final forceRelay = _relayValue(_forceRelay, draft?.forceNextHopMode.value);
    final favoriteRelay = _relayValue(
      _favoriteRelay,
      draft?.favoriteRouterMode.value,
    );
    final edited = draft == null || forceRelay == null || favoriteRelay == null
        ? null
        : (draft.deepCopy()
            ..forceNextHopRelay = forceRelay
            ..favoriteRouterRelay = favoriteRelay);
    final canSave =
        editable &&
        edited != null &&
        (_saved == null || edited.values != _saved?.values);
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
        if (draft == null && editable)
          SectionCard(
            footer: strings.tmeshLegacyDescription,
            children: [
              MeshTile(
                title: strings.tmeshLegacyTitle,
                leading: const Icon(Icons.history),
              ),
              MeshTile(
                title: strings.tmeshCreate,
                leading: const Icon(Icons.add),
                onTap: () =>
                    setState(() => _setDraft(tmesh.FeatureFlagsConfig())),
              ),
            ],
          ),
        if (draft != null) ...[
          KeyedSubtree(
            key: ValueKey(_formVersion),
            child: _fields(strings, draft, editable, forceRelay, favoriteRelay),
          ),
          if (_saved == null) WarningNote(strings.tmeshCreateDescription),
          Padding(
            padding: const EdgeInsets.all(Tokens.s16),
            child: FilledButton(
              onPressed: canSave ? () => _save(edited) : null,
              child: Text(
                _saved == null ? strings.tmeshCreate : strings.save_486405,
              ),
            ),
          ),
          if (_saved != null)
            Center(
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: editable ? _clear : null,
                child: Text(strings.tmeshClear),
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
    int? forceRelay,
    int? favoriteRelay,
  ) => Column(
    children: [
      SectionCard(
        title: strings.tmeshRouting,
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
            value: draft.restrictedRoutingDisallowsPrivateText,
            onChanged: editable
                ? (value) => setState(
                    () => draft.restrictedRoutingDisallowsPrivateText = value,
                  )
                : null,
          ),
          _choice<tmesh.FeatureFlagsConfig_HopDecrementMode>(
            label: strings.tmeshHopDecrement,
            value: draft.hopDecrementMode,
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
            value: _forceRelay,
            valid: forceRelay != null,
            requiredByte: draft.forceNextHopMode.value != 0,
            enabled: editable,
            onChanged: (value) => setState(() => _forceRelay = value),
          ),
        ],
      ),
      SectionCard(
        title: strings.tmeshFavoriteRouter,
        footer: strings.tmeshRelayDescription,
        children: [
          _choice<tmesh.FeatureFlagsConfig_FavoriteRouterMode>(
            label: strings.tmeshMode,
            value: draft.favoriteRouterMode,
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
            value: _favoriteRelay,
            valid: favoriteRelay != null,
            requiredByte: draft.favoriteRouterMode.value != 0,
            enabled: editable,
            onChanged: (value) => setState(() => _favoriteRelay = value),
          ),
        ],
      ),
    ],
  );

  Widget _relayField({
    required String value,
    required bool valid,
    required bool requiredByte,
    required bool enabled,
    required ValueChanged<String> onChanged,
  }) {
    final strings = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(Tokens.s16),
      child: TextFormField(
        initialValue: value,
        enabled: enabled,
        autocorrect: false,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: strings.tmeshRelay,
          errorMaxLines: 2,
          errorText: valid
              ? null
              : requiredByte
              ? strings.tmeshRelayRequired
              : strings.tmeshRelayRange,
        ),
      ),
    );
  }

  Widget _choice<T extends ProtobufEnum>({
    required String label,
    required T value,
    required List<T> values,
    required List<String> labels,
    required ValueChanged<T>? onChanged,
  }) => Padding(
    padding: const EdgeInsets.all(Tokens.s16),
    child: DropdownButtonFormField<T>(
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
  );
}

int? _relayValue(String text, int? mode) {
  final value = int.tryParse(text.trim());
  final min = mode == null || mode == 0 ? 0 : 1;
  return value != null && value >= min && value <= 255 ? value : null;
}

void _mergeEdits(
  tmesh.FeatureFlagsConfig fresh,
  tmesh.FeatureFlagsConfig? saved,
  tmesh.FeatureFlagsConfig edited,
) {
  if (saved?.restrictedRoutingMode != edited.restrictedRoutingMode) {
    fresh.restrictedRoutingMode = edited.restrictedRoutingMode;
  }
  if (saved?.restrictedRoutingDisallowsPrivateText !=
      edited.restrictedRoutingDisallowsPrivateText) {
    fresh.restrictedRoutingDisallowsPrivateText =
        edited.restrictedRoutingDisallowsPrivateText;
  }
  if (saved?.hopDecrementMode != edited.hopDecrementMode) {
    fresh.hopDecrementMode = edited.hopDecrementMode;
  }
  if (saved?.forceNextHopMode != edited.forceNextHopMode) {
    fresh.forceNextHopMode = edited.forceNextHopMode;
  }
  if (saved?.forceNextHopRelay != edited.forceNextHopRelay) {
    fresh.forceNextHopRelay = edited.forceNextHopRelay;
  }
  if (saved?.favoriteRouterMode != edited.favoriteRouterMode) {
    fresh.favoriteRouterMode = edited.favoriteRouterMode;
  }
  if (saved?.favoriteRouterRelay != edited.favoriteRouterRelay) {
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
