/// Story 2.3's (spec-2-3) fixed idle re-authentication threshold.
/// Domain-owned per the epic's Technical Decisions — never a shared
/// `core/` constant, never user-configurable (AC2: re-authentication is
/// always prompted at or past this threshold, regardless of any user
/// setting), never re-tuned by any later story.
///
/// Compared against elapsed time since `AppLifecycleState.paused` was last
/// observed while the vault was unlocked — see `VaultRepositoryImpl`'s
/// `didChangeAppLifecycleState` override.
const Duration vaultIdleTimeout = Duration(minutes: 5);
