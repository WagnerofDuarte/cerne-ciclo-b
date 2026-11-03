/// The epic's one session-status enum (AD — "exactly one `SessionStatus`
/// stream exposed from the auth feature's domain layer"). No `loading`/`idle`
/// member: a `StreamBuilder` with no data yet is this story's "loading"
/// representation (`main.dart`), never an extra enum value for that.
///
/// Story 1.5 adds [expired] — a mid-session `AUTH_EXPIRED` while
/// [authenticated], signalled via `SessionExpiryNotifier` and bridged onto
/// this same stream by `SessionRepositoryImpl`. `main.dart` renders the
/// same authenticated screen for both [authenticated] and [expired],
/// showing a recovery overlay only for the latter — never a third screen.
/// Per the spec's "Ask First" boundary, a future fourth value requires
/// renegotiating the epic's AD before being added.
enum SessionStatus { authenticated, unauthenticated, expired }
