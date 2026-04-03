# Contract: Speech State File Schema

**File**: `$env:TEMP/voice-status-state.json`
**Purpose**: Cross-process coordination for rate limiting and deduplication.

## Schema

```json
{
  "lastSpokenAt": 1704614700000,
  "recentMessages": [
    {
      "hash": "a1b2c3d4e5f6",
      "spokenAt": 1704614700000
    }
  ]
}
```

## Field Definitions

| Field | Type | Description |
|-------|------|-------------|
| `lastSpokenAt` | integer (Unix ms) | Timestamp of last spoken message. Used for global rate limiting. |
| `recentMessages` | `RecentMessage[]` | Array of recently spoken message hashes. Used for deduplication. |
| `recentMessages[].hash` | string | Case-insensitive hash of spoken text (produced by PowerShell `GetHashCode()` or similar) |
| `recentMessages[].spokenAt` | integer (Unix ms) | When this message was spoken |

## Concurrency Model

- **Last-write-wins**: No file locking. Each hook invocation reads the current state, makes its decision, and writes the updated state.
- **Race condition tolerance**: If two hooks fire simultaneously, one may overwrite the other's state update. This can result in an occasional extra spoken message, which is acceptable for a notification system.
- **Atomic write pattern**: Write to a temp file, then rename (Move-Item) to minimize partial-read risk.

## Lifecycle

- **Created**: On first spoken message in a session
- **Updated**: On each spoken message (append to recentMessages, update lastSpokenAt)
- **Cleaned**: Expired entries (older than dedupWindowMs) pruned on each read
- **Deleted**: Not actively deleted; relies on OS temp directory cleanup. Benign if missing — recreated on next speech.

## Size Constraints

- `recentMessages` array is bounded by the dedup window — entries older than `dedupWindowMs` are pruned on every read
- In practice, with a 3s rate limit and 10s dedup window, the array never exceeds ~4 entries
