import 'package:flutter/material.dart';

import '../../../../core/design_tokens.dart';
import '../../domain/entities/entry.dart';
import '../../domain/entities/sync_badge_state.dart';
import 'sync_badge.dart';

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
/// (the deleted `HomeChatPlaceholderScreen`'s own chat icon, now
/// `ChatScreen`'s own `_ChatBootstrapErrorView`).
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
/// [Entry.source], a source icon, the local time, a content excerpt, and
/// (spec-4-2) its own [SyncBadge]. spec-4-4: [onTap] is this card's one
/// navigation affordance — it opens `EntryDetailScreen`
/// (`MeusRegistrosScreen`'s own wiring), scoped to the card's body; the
/// only other `InkWell` anywhere in this subtree still lives inside
/// [SyncBadge] itself, scoped to the badge's own tap target, so a tap
/// landing on the badge triggers retry, never navigation.
class EntryRecordCard extends StatelessWidget {
  const EntryRecordCard({
    required this.entry,
    required this.badgeState,
    required this.onTap,
    this.onRetryTap,
    super.key,
  });

  final Entry entry;

  /// This card's own badge (Code Map: `deriveSyncBadgeState()`'s result)
  /// — computed by the caller (`MeusRegistrosLoaded.badgeFor`), never
  /// recomputed here (Never: "any screen recomputing badge state inline").
  final SyncBadgeState badgeState;

  /// spec-4-4 — opens this entry's detail view
  /// (`MeusRegistrosScreen`'s `context.push('${AppRoutePaths.
  /// meusRegistros}/${Uri.encodeComponent(entry.id)}')` — the id is
  /// URL-encoded, round-1 review fix). A pending/failed placeholder's own
  /// synthetic `tempId` is a valid, un-special-cased target here too
  /// (Boundaries) — this card never knows or cares which kind of id it
  /// holds.
  final VoidCallback onTap;

  /// Forwarded to [SyncBadge] verbatim — only ever invoked for a
  /// retryable [SyncBadgeError].
  final VoidCallback? onRetryTap;

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
        // Review finding, round 1: the tappable area must cover the whole
        // card — including the colored spine strip beside the content, not
        // just the content `Padding` — so `Material`/`InkWell` now wraps
        // the entire `Stack` rather than only its second child.
        // `SyncBadge`'s own nested `InkWell` still wins the hit test for a
        // tap landing on the badge itself.
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
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
                          // Correction: `cerne-prototype.html`'s own record
                          // card puts the sync indicator on the right of
                          // this same row, next to the time — not below
                          // the content excerpt.
                          SyncBadge(
                            state: badgeState,
                            onRetryTap: onRetryTap,
                            compact: true,
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
  final local = DateTime.tryParse(occurredAt)?.toLocal();
  if (local == null) {
    return '--:--';
  }
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
