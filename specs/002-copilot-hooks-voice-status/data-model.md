# Data Model: Copilot Agent Hooks Voice Status

**Branch**: `002-copilot-hooks-voice-status` | **Date**: 2026-04-03

## Entities

### Hook Event Payloads (Input — read-only, from agent runtime)

These are the JSON objects received on stdin by each hook script. They are defined by the GitHub Copilot hooks protocol and are not modifiable.

#### SessionStartPayload

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | integer (Unix ms) | When the event occurred |
| `cwd` | string | Current working directory |
| `source` | enum: `"new"`, `"resume"`, `"startup"` | How the session started |
| `initialPrompt` | string (optional) | The user's initial prompt text |

#### SessionEndPayload

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | integer (Unix ms) | When the event occurred |
| `cwd` | string | Current working directory |
| `reason` | enum: `"complete"`, `"error"`, `"abort"`, `"timeout"`, `"user_exit"` | Why the session ended |

#### UserPromptSubmittedPayload

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | integer (Unix ms) | When the event occurred |
| `cwd` | string | Current working directory |
| `prompt` | string | The exact text the user submitted |

#### PostToolUsePayload

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | integer (Unix ms) | When the event occurred |
| `cwd` | string | Current working directory |
| `toolName` | string | Name of the tool (e.g., "edit", "bash", "view") |
| `toolArgs` | string (JSON) | Stringified JSON of tool arguments |
| `toolResult.resultType` | enum: `"success"`, `"failure"`, `"denied"` | Outcome of tool execution |
| `toolResult.textResultForLlm` | string | Result text shown to the agent |

#### ErrorOccurredPayload

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | integer (Unix ms) | When the event occurred |
| `cwd` | string | Current working directory |
| `error.message` | string | Error message |
| `error.name` | string | Error type/name |
| `error.stack` | string (optional) | Stack trace |

### Speech State (file-persisted across hook invocations)

Location: `$env:TEMP/voice-status-state.json`

| Field | Type | Description |
|-------|------|-------------|
| `lastSpokenAt` | integer (Unix ms) | Timestamp of last spoken message (for rate limiting) |
| `recentMessages` | array of `RecentMessage` | Ring buffer of recent message hashes (for dedup) |

#### RecentMessage

| Field | Type | Description |
|-------|------|-------------|
| `hash` | string | Lowercase hash of the spoken text |
| `spokenAt` | integer (Unix ms) | When this message was spoken |

**Lifecycle**: Created on first speech. Updated on each spoken message. Expired entries pruned on each read. File deleted when no longer needed (manual cleanup or OS temp cleanup).

**Concurrency**: Last-write-wins. No file locking. Occasional duplicate speech is acceptable.

### Voice Status Configuration (user-editable JSON)

Location: `.github/hooks/scripts/voice-status-config.json`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `interestingTools` | string[] | `["edit","create","bash","powershell","write_powershell","task"]` | Tools that trigger spoken summaries |
| `noisyTools` | string[] | `["view","grep","glob","read_powershell","list_powershell","web_fetch"]` | Tools explicitly silenced |
| `rateLimitMs` | integer | `3000` | Minimum ms between spoken messages |
| `dedupWindowMs` | integer | `10000` | Window in ms to suppress duplicate messages |
| `ttsTimeoutMs` | integer | `30000` | Max ms to wait for TTS process |
| `voiceRate` | integer | `0` | Speech rate (-10 to 10) |
| `voiceVolume` | integer | `100` | Speech volume (0 to 100) |

**Override precedence**: Environment variables > JSON config > built-in defaults.

**Environment variable mapping**:

| Env Var | Config Field |
|---------|-------------|
| `VOICE_STATUS_RATE_LIMIT_MS` | `rateLimitMs` |
| `VOICE_STATUS_DEDUP_WINDOW_MS` | `dedupWindowMs` |
| `VOICE_STATUS_TIMEOUT_MS` | `ttsTimeoutMs` |
| `VOICE_STATUS_VOLUME` | `voiceVolume` |
| `VOICE_STATUS_RATE` | `voiceRate` |

### Hook Configuration (Copilot protocol)

Location: `.github/hooks/voice-status.json`

This is not a custom entity — it follows the standard Copilot hooks `version: 1` schema. Included here for completeness.

| Field | Type | Description |
|-------|------|-------------|
| `version` | integer | Always `1` |
| `hooks` | object | Map of event names to arrays of hook entries |
| `hooks.<event>[].type` | string | Always `"command"` |
| `hooks.<event>[].powershell` | string | PowerShell command or script path |
| `hooks.<event>[].cwd` | string | Working directory for the script |
| `hooks.<event>[].timeoutSec` | integer | Timeout in seconds |
| `hooks.<event>[].env` | object (optional) | Additional environment variables |

## State Transitions

### Speech Decision Flow (per hook invocation)

```
Hook Invoked
  ├─ Parse JSON from stdin
  │   └─ Parse failure → exit 0 silently
  ├─ Determine message (event-specific logic)
  │   └─ No message needed (noisy tool, no prompt, etc.) → exit 0
  ├─ Check rate limit (skip for errors)
  │   └─ Rate limited → exit 0
  ├─ Check dedup
  │   └─ Duplicate → exit 0
  ├─ Sanitize text
  ├─ Truncate to 200 chars
  ├─ Update state file (lastSpokenAt + add to recentMessages)
  ├─ Launch TTS background job
  └─ Exit 0
```

### State File Lifecycle

```
Not Exists → First Speech → Created with initial entry
  → Subsequent Speech → Updated (append recent, update lastSpokenAt)
  → Read with cleanup → Expired entries pruned
  → OS temp cleanup → Deleted (benign; recreated on next speech)
```
