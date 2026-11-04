import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../entries/domain/entities/entry.dart';
import '../../../entries/domain/repositories/entries_repository.dart';

/// The Insertion Modal's 3 tabs — Boundaries: "3 equal-width tabs (Texto/
/// Áudio/Foto)". Only [texto] is functional this story; [audio]/[foto]
/// render idle, non-interactive placeholders (Stories 3.2/3.3).
enum CaptureTab { texto, audio, foto }

/// Capture's own state for the Insertion Modal — never the shared
/// `Resource<T>` (Boundaries). A sealed class, not `freezed` (no codegen
/// for this story beyond `entry_dto.g.dart`, Verification): every
/// variant always carries the common [activeTab]/[text] so switching tabs
/// or typing never needs to know which variant it's coming from.
sealed class TextEntryState {
  const TextEntryState({required this.activeTab, required this.text});

  final CaptureTab activeTab;
  final String text;
}

/// Ready to type/save — the state immediately after the modal opens
/// (Boundaries: "Opens on Texto, all 3 tabs idle/empty"), after a tab
/// switch, and after a keystroke.
class TextEntryIdle extends TextEntryState {
  const TextEntryIdle({required super.activeTab, required super.text});
}

/// Salvar tapped, `POST /entries` in flight — the I/O matrix's "no
/// auto-retry, no double-submit": `InsertionModal` disables Salvar/the
/// text field for the duration of this state.
class TextEntrySaving extends TextEntryState {
  const TextEntrySaving({required super.activeTab, required super.text});
}

/// The save attempt succeeded — `InsertionModal`'s listener reacts to
/// this by popping the sheet (I/O matrix: "success closes the modal").
/// Terminal: nothing meaningful follows it for this cubit instance, since
/// the modal (and the factory-scoped cubit backing it) is already
/// closing.
class TextEntrySaved extends TextEntryState {
  const TextEntrySaved({required super.activeTab, required super.text});
}

/// The last save attempt failed (incl. offline, via the existing
/// `Failure.networkOffline`) — [message] is `Failure.message` verbatim
/// (I/O matrix: "Inline message from `Failure.message`"); Salvar is
/// re-enabled, the modal stays open, no auto-retry.
class TextEntryError extends TextEntryState {
  const TextEntryError({
    required super.activeTab,
    required super.text,
    required this.message,
  });

  final String message;
}

/// Drives `InsertionModal`. Calls [EntriesRepository.create] directly on
/// [save] — no use-case layer, matching this codebase's existing
/// convention (Design Notes: `AccountSettingsCubit`/`AuthCubit`). A fresh,
/// `get_it`-factory-scoped instance per "+" tap (Boundaries: "Modal open
/// resets") — starting state is always [TextEntryIdle] on
/// [CaptureTab.texto] with empty text, so no explicit reset method is
/// needed the way `AccountSettingsCubit.clearStaleError()` needs one for
/// its own long-lived singleton.
class TextEntryCubit extends Cubit<TextEntryState> {
  TextEntryCubit(this._repository)
    : super(const TextEntryIdle(activeTab: CaptureTab.texto, text: ''));

  final EntriesRepository _repository;

  /// Switches the active tab, preserving whatever Texto text was already
  /// typed (Never: the full cross-tab cancel-safety rule is Story 3.4's
  /// scope — this story's trivial case just needs the tab itself to
  /// switch without losing in-progress text or firing any `create` call).
  ///
  /// Review finding: ignored while [TextEntrySaving] — `InsertionModal`
  /// already disables the tab bar for that case, but this is the
  /// authoritative guard regardless of how `selectTab` is invoked. Without
  /// it, switching away mid-save would still let `save()`'s eventual
  /// `TextEntrySaved`/`TextEntryError` emission land on top of whatever
  /// tab/text the user has since moved to — popping the modal
  /// unexpectedly, or showing an error against an unrelated tab.
  void selectTab(CaptureTab tab) {
    if (tab == state.activeTab || state is TextEntrySaving) {
      return;
    }
    emit(TextEntryIdle(activeTab: tab, text: state.text));
  }

  /// Mirrors the Texto field's own `TextEditingController` into this
  /// cubit's state, so [save] has the latest typed text to send. Ignored
  /// while a save is already in flight — the field is disabled in that
  /// state (`InsertionModal`), so this should never fire then regardless.
  void updateText(String text) {
    if (state is TextEntrySaving) {
      return;
    }
    emit(TextEntryIdle(activeTab: state.activeTab, text: text));
  }

  /// I/O matrix's "Happy path save"/"Save fails" rows: fires `POST
  /// /entries` with `source: manual` (Boundaries — the only source this
  /// story ever sends) for whatever non-empty text is currently typed. A
  /// blank/whitespace-only text never calls [EntriesRepository.create] —
  /// `InsertionModal` already disables Salvar for that case, but this is
  /// the authoritative guard regardless of how `save()` is invoked.
  ///
  /// Review finding: also ignored while already [TextEntrySaved] — the
  /// modal's dismiss animation keeps this cubit alive (and Salvar
  /// re-enabled, since that state isn't [TextEntrySaving]) for its
  /// duration, so without this a fast double-tap on Salvar could fire a
  /// second, un-deduplicated `create` call before the sheet finishes
  /// closing.
  Future<void> save() async {
    final text = state.text.trim();
    if (text.isEmpty || state is TextEntrySaving || state is TextEntrySaved) {
      return;
    }
    final activeTab = state.activeTab;
    emit(TextEntrySaving(activeTab: activeTab, text: text));
    final result = await _repository.create(
      content: text,
      source: EntrySource.manual,
    );
    // Mirrors `AccountSettingsCubit.toggleBiometric`'s own guard: this
    // cubit's `dispose:`/`close()` can race the awaited call above (e.g.
    // the modal's barrier is dismissed mid-save) — `emit()` after `close()`
    // would otherwise throw.
    if (isClosed) {
      return;
    }
    result.match(
      (failure) => emit(
        TextEntryError(activeTab: activeTab, text: text, message: failure.message),
      ),
      (_) => emit(TextEntrySaved(activeTab: activeTab, text: text)),
    );
  }
}
