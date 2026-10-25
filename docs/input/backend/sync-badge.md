# Synchronization badge semantics

There is no `sync_status` column in the database: the architecture is cloud-only, so "it is on the server" already means "synchronized", by definition. The server neither stores nor computes a synchronization state; it only exposes two fields, and the **badge is derived entirely in the app** from them:

| Field | Where it appears in the contract | Meaning |
|---|---|---|
| `updatedAt` | `Entry.updatedAt` | Timestamp of the last server write for that entry. |
| `serverRevision` | `Entry.serverRevision`, and also in the profile | Counter that increases with every write to the user's entries — never resets, never decreases. |

**The badge's 3 states, all inferred on the client — none comes ready from the server:**
1. **Synchronizing** — the app has a local write not yet confirmed by the server (it has not yet received the response with the new `updatedAt`/`serverRevision`).
2. **Synchronization error** — the write was attempted and failed (network, or one of the 13 codes of the error taxonomy) and the app has not yet been able to reconcile.
3. **Synchronized** — the last confirmed write matched; nothing is pending on the client side for that entry.

When to show each state is not decided by the server: the reconciliation logic lives in the client, using exactly these two fields.
