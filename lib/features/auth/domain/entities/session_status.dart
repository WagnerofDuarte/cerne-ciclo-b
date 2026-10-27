/// The epic's one two-state session status (AD — "exactly one `SessionStatus`
/// stream exposed from the auth feature's domain layer"). No `loading`/`idle`
/// member: a `StreamBuilder` with no data yet is this story's "loading"
/// representation (`main.dart`), never a third enum value.
enum SessionStatus { authenticated, unauthenticated }
