import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/sticker_providers.dart';
import '../../core/stickers/wire_codec.dart';
import '../../l10n/l10n.dart';
import '../stickers/sticker_library_page.dart';
import '../stickers/sticker_offer_page.dart';

class StickerMessageBody extends ConsumerWidget {
  const StickerMessageBody({
    super.key,
    required this.envelope,
    this.compact = false,
  });
  final StickerEnvelope envelope;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installed = ref.watch(installedStickersProvider);
    final pack = installed.value
        ?.where((p) => p.hash == envelope.packSha256)
        .firstOrNull;
    final sticker = pack?.manifest.stickers
        .where((s) => s.id == envelope.stickerId)
        .firstOrNull;
    // Hash lookup wins over source trust: an already installed image works even
    // when this message references an unknown, offline or blocked origin.
    if (sticker != null) {
      final size = compact ? 32.0 : 176.0;
      return Semantics(
        label: sticker.alt,
        image: true,
        child: Tooltip(
          message: sticker.alt,
          child: SizedBox.square(
            dimension: size,
            child: compact
                ? StickerImage(
                    hash: envelope.packSha256,
                    sticker: sticker,
                    still: true,
                  )
                : InkWell(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(sticker.alt),
                        content: SizedBox.square(
                          dimension: 240,
                          child: StickerImage(
                            hash: envelope.packSha256,
                            sticker: sticker,
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(
                              MaterialLocalizations.of(ctx).closeButtonLabel,
                            ),
                          ),
                        ],
                      ),
                    ),
                    child: StickerImage(
                      hash: envelope.packSha256,
                      sticker: sticker,
                      still: true,
                    ),
                  ),
          ),
        ),
      );
    }
    final localError =
        installed.hasError ||
        ref
            .read(stickerPackRepositoryProvider)
            .damagedHashes
            .contains(envelope.packSha256);
    final label = localError
        ? context.l10n.stickerLocalError
        : installed.isLoading
        ? context.l10n.stickerCheckingLocal
        : pack != null
        ? context.l10n.stickerMissingId
        : context.l10n.stickerMissingPack;
    if (compact) {
      return Tooltip(
        message: label,
        child: Icon(
          localError
              ? Icons.broken_image_outlined
              : Icons.sticky_note_2_outlined,
          size: 28,
          semanticLabel: label,
        ),
      );
    }
    final sources = ref.watch(stickerLocalSourcesProvider);
    final blocked =
        sources.value?.any(
          (s) => s.url == envelope.sourceUrl && s.record.blocked,
        ) ==
        true;
    return SizedBox(
      width: 200,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            localError
                ? Icons.broken_image_outlined
                : Icons.sticky_note_2_outlined,
          ),
          Text(
            blocked && pack == null ? context.l10n.stickerSourceBlocked : label,
          ),
          if (pack == null)
            Text(
              Uri.parse(envelope.sourceUrl).host,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (!installed.isLoading && pack == null)
            TextButton(
              onPressed: sources.isLoading
                  ? null
                  : () => Navigator.of(context, rootNavigator: true).push<void>(
                      MaterialPageRoute(
                        builder: (_) => StickerOfferPage(envelope: envelope),
                      ),
                    ),
              child: Text(context.l10n.stickerSourceAndPack),
            ),
        ],
      ),
    );
  }
}
