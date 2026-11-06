/// spec-6-5 — `ChatCubit`'s own per-session window: once this many user
/// messages have been sent via `sendMessage` (never `retryMessage`,
/// Boundaries) since the window opened, the `message_count` trigger
/// fires. Mirrors `vault_idle_timeout.dart`'s standalone-constant
/// convention: domain-owned, never user-configurable.
const int insightMessageCountThreshold = 5;

/// The default inactivity timeout racing [insightMessageCountThreshold]
/// for the same window — whichever is satisfied first wins (Boundaries).
/// `ChatCubit`'s own constructor accepts an override purely as a test
/// seam (Design Notes); production never passes anything else.
const Duration defaultInsightInactivityTimeout = Duration(minutes: 2);
