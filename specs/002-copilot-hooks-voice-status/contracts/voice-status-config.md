# Contract: Voice Status Configuration Schema

**File**: `.github/hooks/scripts/voice-status-config.json`
**Purpose**: User-editable settings for voice status behavior, designed for future VS Code extension UI management.

## Schema

```json
{
  "$schema": "voice-status-config-schema",
  "interestingTools": ["edit", "create", "bash", "powershell", "write_powershell", "task"],
  "noisyTools": ["view", "grep", "glob", "read_powershell", "list_powershell", "web_fetch"],
  "rateLimitMs": 3000,
  "dedupWindowMs": 10000,
  "ttsTimeoutMs": 30000,
  "voiceRate": 0,
  "voiceVolume": 100
}
```

## Field Definitions

| Field | Type | Range | Default | Description |
|-------|------|-------|---------|-------------|
| `interestingTools` | `string[]` | any tool names | see above | Tools that trigger spoken summaries in postToolUse |
| `noisyTools` | `string[]` | any tool names | see above | Tools explicitly suppressed (informational; unrecognized tools are also suppressed) |
| `rateLimitMs` | `integer` | 1000–60000 | 3000 | Minimum milliseconds between spoken messages |
| `dedupWindowMs` | `integer` | 1000–120000 | 10000 | Window in milliseconds for suppressing duplicate messages |
| `ttsTimeoutMs` | `integer` | 5000–120000 | 30000 | Maximum milliseconds for TTS background job before kill |
| `voiceRate` | `integer` | -10 to 10 | 0 | Speech rate (negative = slower, positive = faster) |
| `voiceVolume` | `integer` | 0–100 | 100 | Speech volume percentage |

## Override Precedence

```
Environment Variable  >  JSON Config File  >  Built-in Default
```

## Environment Variable Mapping

| Environment Variable | Config Field | Example |
|---------------------|-------------|---------|
| `VOICE_STATUS_RATE_LIMIT_MS` | `rateLimitMs` | `5000` |
| `VOICE_STATUS_DEDUP_WINDOW_MS` | `dedupWindowMs` | `15000` |
| `VOICE_STATUS_TIMEOUT_MS` | `ttsTimeoutMs` | `60000` |
| `VOICE_STATUS_VOLUME` | `voiceVolume` | `50` |
| `VOICE_STATUS_RATE` | `voiceRate` | `2` |

## Validation Rules

- All integer fields are clamped to their valid range (not rejected)
- Tool name arrays accept any non-empty strings
- Missing fields use built-in defaults
- Malformed JSON → fall back to all built-in defaults (log warning to stderr)
- File not found → use all built-in defaults (no error)

## Extension UI Considerations

This JSON structure is designed to be directly manageable by a VS Code extension settings UI:
- Flat structure (no nesting beyond arrays)
- All fields have simple types (string arrays, integers)
- Clear min/max ranges for validation
- File path is deterministic relative to repo root
