import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/sticker_providers.dart';
import '../../data/stickers/pack_repository.dart';
import '../../l10n/l10n.dart';
import '../stickers/sticker_library_page.dart';

typedef StickerSelection = ({String packSha256, String stickerId});

Future<StickerSelection?> showStickerPicker(BuildContext context) =>
    showModalBottomSheet<StickerSelection>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => const StickerPicker(),
    );

/// The picker is strictly local. Source editing and network operations live in
/// the library, and never run merely because this panel was opened.
class StickerPicker extends ConsumerStatefulWidget {
  const StickerPicker({super.key});
  @override
  ConsumerState<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends ConsumerState<StickerPicker> {
  String? _selected;
  @override
  Widget build(BuildContext context) {
    final installed = ref.watch(installedStickersProvider);
    final sources = ref.watch(stickerLocalSourcesProvider);
    final canSend = ref.watch(canSendProvider);
    final packs = installed.value ?? const <InstalledStickerPack>[];
    final pack = packs.where((p) => p.hash == _selected).firstOrNull;
    final recent = ref.watch(recentStickersProvider);
    final items = _selected == null
        ? [
            for (final entry in recent.value ?? const <RecentSticker>[])
              for (final p in packs.where((p) => p.hash == entry.packSha256))
                for (final sticker in p.manifest.stickers.where(
                  (s) => s.id == entry.stickerId,
                ))
                  (pack: p, sticker: sticker),
          ]
        : [
            if (pack != null)
              for (final sticker in pack.manifest.stickers)
                (pack: pack, sticker: sticker),
          ];
    final blocked =
        pack != null &&
        sources.value?.any(
              (s) => s.url == pack.preferredSourceUrl && s.record.blocked,
            ) ==
            true;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.stickersTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.stickerManagePacks,
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => showStickerLibrary(context),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            if (!canSend)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(context.l10n.connectToANodeToSend_67b4d9),
              ),
            if (blocked)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(context.l10n.stickerSendingBlocked),
              ),
            if (installed.hasError || sources.hasError)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(context.l10n.stickerLoadFailed),
              ),
            if (installed.isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (packs.isEmpty)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      context.l10n.stickerNoInstalled,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: const Icon(Icons.history, size: 18),
                        label: Text(context.l10n.stickerRecent),
                        selected: _selected == null,
                        onSelected: (_) => setState(() => _selected = null),
                      ),
                    ),
                    for (final p in packs)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: Text(
                              p.manifest.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          selected: _selected == p.hash,
                          onSelected: (_) => setState(() => _selected = p.hash),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            context.l10n.stickerRecentEmpty,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 112,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final (:pack, :sticker) = items[index];
                          final enabled =
                              canSend &&
                              sources.hasValue &&
                              !sources.hasError &&
                              !sources.value!.any(
                                (s) =>
                                    s.url == pack.preferredSourceUrl &&
                                    s.record.blocked,
                              );
                          return Semantics(
                            label: sticker.alt,
                            button: true,
                            enabled: enabled,
                            child: Tooltip(
                              message: sticker.alt,
                              child: Material(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(12),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: enabled
                                      ? () => Navigator.pop(context, (
                                          packSha256: pack.hash,
                                          stickerId: sticker.id,
                                        ))
                                      : null,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: StickerImage(
                                      hash: pack.hash,
                                      sticker: sticker,
                                      still: true,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
