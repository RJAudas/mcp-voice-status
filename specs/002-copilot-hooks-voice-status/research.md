# Research: Copilot Agent Hooks Voice Status

**Branch**: `002-copilot-hooks-voice-status` | **Date**: 2026-04-03

## Research Tasks

### 1. GitHub Copilot Hooks Protocol

**Decision**: Use the standard `.github/hooks/` JSON configuration with `version: 1` format.

**Rationale**: This is the documented hooks protocol supported by both Copilot cloud agent and Copilot CLI. The format is stable, uses a simple JSON schema, and hooks load automatically from the repo's default branch (cloud agent) or current working directory (CLI).

**Alternatives considered**:
- Custom hook loading mechanism — rejected; would break compatibility with both agent runtimes
- MCP-based approach (existing) — rejected; requires explicit agent cooperation, which the pivot specifically avoids

**Key findings from documentation**:
- Hook config location: `.github/hooks/<name>.json` (any filename)
- Format: `{ "version": 1, "hooks": { "<eventName>": [{ "type": "command", "powershell": "...", "cwd": ".", "timeoutSec": N }] } }`
- Available hook events: `sessionStart`, `sessionEnd`, `userPromptSubmitted`, `preToolUse`, `postToolUse`, `errorOccurred`
- Scripts receive JSON on stdin via `[Console]::In.ReadToEnd() | ConvertFrom-Json`
- Output is ignored for all hooks except `preToolUse` (which can return permission decisions)
- Default timeout: 30 seconds per hook
- Multiple hooks per event execute in order

### 2. Hook Event Payloads (stdin JSON)

**Decision**: Parse the documented payload schemas directly; no wrapper or transformation needed.

**Payload schemas** (from GitHub documentation):

| Event | Key Fields |
|-------|-----------|
| `sessionStart` | `timestamp`, `cwd`, `source` ("new"/"resume"/"startup"), `initialPrompt` |
| `sessionEnd` | `timestamp`, `cwd`, `reason` ("complete"/"error"/"abort"/"timeout"/"user_exit") |
| `userPromptSubmitted` | `timestamp`, `cwd`, `prompt` |
| `preToolUse` | `timestamp`, `cwd`, `toolName`, `toolArgs` (JSON string) |
| `postToolUse` | `timestamp`, `cwd`, `toolName`, `toolArgs` (JSON string), `toolResult.resultType` ("success"/"failure"/"denied"), `toolResult.textResultForLlm` |
| `errorOccurred` | `timestamp`, `cwd`, `error.message`, `error.name`, `error.stack` |

**Rationale**: These are the exact schemas from the GitHub docs reference. No additional parsing or normalization layer is needed.

### 3. PowerShell TTS with System.Speech

**Decision**: Use `System.Speech.Synthesis.SpeechSynthesizer` via `Add-Type -AssemblyName System.Speech`, spawned as a background job to avoid blocking.

**Rationale**: This is the same proven approach from the existing TypeScript codebase (which spawned PowerShell as a child process). System.Speech ships with .NET Framework on every Windows 10/11 machine. No downloads needed.

**Key implementation pattern**:
```powershell
# Fire-and-forget TTS: launch as background job so hook exits immediately
$script = @"
Add-Type -AssemblyName System.Speech
`$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
`$synth.Rate = $rate
`$synth.Volume = $volume
`$synth.Speak('$sanitizedText')
`$synth.Dispose()
"@
Start-Job -ScriptBlock ([ScriptBlock]::Create($script)) | Out-Null
```

**Alternatives considered**:
- Synchronous speech (blocking) — rejected; would block the hook and potentially slow the agent
- SAPI COM object — rejected; more complex, no benefit over .NET wrapper
- External TTS (eSpeak, pyttsx3) — rejected; violates Constitution VI (Windows-Native)

### 4. Text Sanitization Strategy

**Decision**: Port the existing TypeScript sanitizer logic into PowerShell.

**Rationale**: The existing sanitizer in `src/speech/sanitizer.ts` already handles all necessary cases. Direct port ensures no regression.

**Sanitization steps** (from existing codebase):
1. Remove null bytes → replace with space
2. Remove SSML/XML-like tags → replace with space
3. Escape single quotes → double them (`'` → `''`) for PowerShell string safety
4. Remove double quotes → prevent PS string boundary breaks
5. Remove backticks → PS escape character
6. Remove control characters (except tab/newline/CR)
7. Collapse multiple whitespace → single space
8. Trim leading/trailing whitespace
9. Enforce max length (200 chars for spoken text)

### 5. Rate Limiting and Deduplication via Temp Files

**Decision**: Use a single JSON state file at `$env:TEMP/voice-status-state.json` with last-write-wins semantics (no file locking).

**Rationale**: Each hook invocation is a separate PowerShell process — no shared memory is possible. A temp file is the simplest cross-process coordination mechanism. Per the clarification, occasional duplicate speech from race conditions is acceptable for a notification system.

**State file schema**:
```json
{
  "lastSpokenAt": 1704614700000,
  "recentMessages": [
    { "hash": "abc123...", "spokenAt": 1704614700000 },
    { "hash": "def456...", "spokenAt": 1704614690000 }
  ]
}
```

**Rate limiting**: Compare `lastSpokenAt` against current time. If delta < configured interval (default 3000ms), skip. Error messages bypass this check.

**Deduplication**: Hash the message text (case-insensitive). Check if hash exists in `recentMessages` with `spokenAt` within the dedup window (default 10000ms). If so, skip. Expired entries are cleaned on each read.

**Alternatives considered**:
- Named mutex / semaphore — rejected; adds complexity for negligible benefit
- File locking (lock file) — rejected; risk of stale locks if process crashes; adds complexity
- No persistence (per-process only) — rejected; rate limiting wouldn't work across rapid hook invocations

### 6. Tool Classification for postToolUse Filtering

**Decision**: Maintain an extensible JSON config file mapping tool names to "interesting" or "noisy" categories.

**Rationale**: Per the clarification, the infrastructure should support future VS Code extension UI management. A JSON config file is machine-readable, easily validated, and can be generated/updated by an extension.

**Default classification**:
```json
{
  "interestingTools": ["edit", "create", "bash", "powershell", "write_powershell", "task"],
  "noisyTools": ["view", "grep", "glob", "read_powershell", "list_powershell", "web_fetch"]
}
```

**Behavior**: If a tool name is not in either list, it is treated as noisy (per FR-008).

### 7. Pester Testing Framework

**Decision**: Use Pester 5.x for all tests.

**Rationale**: Pester is the de facto standard for PowerShell testing. It supports unit tests, mocking, and integration tests. It ships with Windows 10+ (Pester 3.x preinstalled, but 5.x is recommended and easy to install via `Install-Module`).

**Testing strategy**:
- **Unit tests**: Test sanitization functions, rate limiter logic, dedup logic, config loading, tool classification, message summarization — all in `voice-status-common.Tests.ps1`
- **Integration tests**: Pipe sample JSON payloads into each hook script and verify behavior (speech invocation, silent skip, error handling)
- **Mock TTS**: Mock `Start-Job` or the TTS function during tests to avoid actual audio

### 8. Fire-and-Forget Speech Pattern

**Decision**: Hook scripts launch TTS as a PowerShell background job (`Start-Job`) and exit immediately without waiting for speech to complete.

**Rationale**: Constitution II (Agent-Invisible) and FR-016 require hooks to be non-blocking. The hook process must exit as fast as possible so the agent isn't slowed. Speech playback happens in a separate background process.

**Pattern**:
1. Hook script reads JSON from stdin
2. Determines if speech is needed (tool filter, rate limit, dedup)
3. If yes: sanitizes text, launches TTS as a detached background job
4. Hook script exits with code 0 immediately

**Alternatives considered**:
- Synchronous speech + increased `timeoutSec` — rejected; would block agent workflow
- Queuing via named pipe — rejected; overengineered for this use case (Constitution VIII)
