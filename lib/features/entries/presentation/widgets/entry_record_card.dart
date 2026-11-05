import 'package:flutter/material.dart';

import '../../../../core/design_tokens.dart';
import '../../domain/entities/entry.dart';

/// One origin's icon + spine color — `cerne-prototype.html`'s own
/// `sourceMeta` object (Boundaries: "exact hex match"): manual `#1F3D34`
/// (`colorPrimary`), audio `#7C8B6F` (`colorSecondary`), photo `#6B6255`
/// (`colorTextSecondary`), chat `#C98A3E` (`colorAccent`) — all four already
/// exist in `design_tokens.dart`, so this story adds no new color. Icons are
/// built-in Material equivalents of the prototype's Phosphor glyphs (no
/// Phosphor dependency in this project — same approximation rationale
/// `DesignTokens.dialogIconSize`'s doc already gives), each already used
/// elsewhere in the app for the same origin: `Icons.mic`
/// (`insertion_modal.dart`'s Áudio tab), `Icons.image_outlined`
/// (its Foto tab), `Icons.chat_bubble_outline`
/// (`HomeChatPlaceholderScreen`'s own chat icon).
class _SourceMeta {
  const _SourceMeta(this.icon, this.color);

  final IconData icon;
  final Color color;
}

const _sourceMeta = <EntrySource, _SourceMeta>{
  EntrySource.manual: _SourceMeta(
    Icons.edit_outlined,
    DesignTokens.colorPrimary,
  ),
  EntrySource.audio: _SourceMeta(Icons.mic, DesignTokens.colorSecondary),
  EntrySource.photo: _SourceMeta(
    Icons.image_outlined,
    DesignTokens.colorTextSecondary,
  ),
  EntrySource.chat: _SourceMeta(
    Icons.chat_bubble_outline,
    DesignTokens.colorAccent,
  ),
};

/// `MeusRegistrosScreen`'s one record card — mirrors
/// `placeholder_screens.dart`'s `_KanbanCard` structure (colored left
/// spine over a `Stack`, Code Map) but for an [Entry]: spine colored by
/// [Entry.source], a source icon, the local time, and a content excerpt.
/// Boundaries: no sync badge (4.2), never tappable (4.4) — no
/// `GestureDetector`/`InkWell` anywhere in this widget.
class EntryRecordCard extends StatelessWidget {
  const EntryRecordCard({required this.entry, super.key});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final meta = _sourceMeta[entry.source]!;
    final time = _formatTime(entry.occurredAt);

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: DesignTokens.colorSurfaceElevated,
        borderRadius: BorderRadius.all(Radius.circular(DesignTokens.radiusMd)),
        boxShadow: DesignTokens.elevation1,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(
          Radius.circular(DesignTokens.radiusMd),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: DesignTokens.kanbanCardSpineWidth,
              child: ColoredBox(color: meta.color),
            ),
            Padding(
              padding: DesignTokens.kanbanCardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(meta.icon, color: meta.color),
                      const SizedBox(width: DesignTokens.spacingSm),
                      Text(
                        time,
                        style: DesignTokens.textMonoCaption.copyWith(
                          color: DesignTokens.colorTextSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: DesignTokens.spacingXs),
                  Text(
                    entry.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DesignTokens.textBodyMd.copyWith(
                      color: DesignTokens.colorTextPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `occurredAt`'s local wall-clock time, `HH:mm` — presentation's own
/// formatting job (Code Map: `Entry.occurredAt` stays a raw ISO string,
/// "parsed only for grouping" at the domain layer; this is the analogous
/// parse-for-display step, scoped to this one widget). A malformed
/// [occurredAt] returns the `'--:--'` placeholder instead of throwing
/// (RNF09), same defensive rationale `groupEntriesByDate()`'s own guard
/// uses.
String _formatTime(String occurredAt) {
  try {
    final local = DateTime.parse(occurredAt).toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  } catch (_) {
    return '--:--';
  }
}
