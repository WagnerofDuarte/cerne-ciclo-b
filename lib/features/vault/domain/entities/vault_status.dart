/// Epic 2's device-level access gate state (AD-14 seam in
/// `core/navigation/app_router.dart`) — mirrors
/// `features/auth/domain/entities/session_status.dart`'s pattern exactly,
/// but for the *device* gate rather than the *session* gate.
///
/// Unlike [SessionStatus] (nullable at boot, since it needs a network round
/// trip to resolve), [VaultStatus] is known synchronously the instant
/// `VaultRepository` is constructed — [locked] is always the correct answer
/// before any biometric prompt has run, so there's no boot-loading gap here
/// to represent with a third/`null` value. Story 2.2 (PIN fallback) and
/// Story 2.3 (idle-timeout re-lock) are the only features allowed to add to
/// this enum or its emission rules — never this story.
enum VaultStatus { locked, unlocked }
