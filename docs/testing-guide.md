# Manual Testing Guide

A hands-on playbook for verifying Voice Status Hooks work correctly. Each test provides a copy-pasteable PowerShell command, the expected spoken output, and troubleshooting tips.

**Run all tests from your repo root directory.**

---

## Test 0: TTS Smoke Test

Verify that Windows text-to-speech works before testing the hooks.

```powershell
Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$synth.Speak("Voice status test. Audio is working.")
$synth.Dispose()
```

**Expected**: You hear "Voice status test. Audio is working."  
**If silent**: Check Windows audio volume, mute state, and default audio device.

---

## Test 1: Session Start

```powershell
'{"timestamp":"2026-01-01T00:00:00Z","cwd":".","source":"new","initialPrompt":"Fix the authentication bug in login.ts"}' |
    powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File ".github\hooks\scripts\on-session-start.ps1"
```

**Expected speech**: "Session started. Fix the authentication bug in login.ts"  
**Exit code**: `$LASTEXITCODE` should be `0`

---

## Test 2: Session Start — Resume

```powershell
'{"timestamp":"2026-01-01T00:00:00Z","cwd":".","source":"resume","initialPrompt":"Continuing work on the test suite"}' |
    powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File ".github\hooks\scripts\on-session-start.ps1"
```

**Expected speech**: "Session started. Continuing work on the test suite"

---

## Test 3: Session End — Various Reasons

```powershell
# Complete
'{"timestamp":"2026-01-01T00:00:00Z","cwd":".","reason":"complete"}' |
    powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File ".github\hooks\scripts\on-session-end.ps1"
# Expected: "Session complete"

# Wait 4 seconds, then test abort (avoids rate limiting)
Start-Sleep -Seconds 4
'{"timestamp":"2026-01-01T00:00:00Z","cwd":".","reason":"abort"}' |
    powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File ".github\hooks\scripts\on-session-end.ps1"
# Expected: "Session aborted"
```

---

## Test 4: New User Prompt

```powershell
'{"timestamp":"2026-01-01T00:00:00Z","cwd":".","prompt":"Add unit tests for the login controller"}' |
    powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File ".github\hooks\scripts\on-prompt-submitted.ps1"
```

**Expected speech**: "New task: Add unit tests for the login controller"

---

## Test 5: Tool Use — Interesting Tool (edit)

```powershell
# Reset state first
Remove-Item "$env:TEMP\voice-status-state.json" -Force -ErrorAction SilentlyContinue

$payload = @{
    timestamp  = "2026-01-01T00:00:00Z"
    cwd        = "."
    toolName   = "edit"
    toolArgs   = '{"path":"src/auth-controller.ts"}'
    toolResult = @{ resultType = "success"; textResultForLlm = "File updated." }
} | ConvertTo-Json -Compress

$payload | powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File ".github\hooks\scripts\on-post-tool-use.ps1"
```

**Expected speech**: "Edited auth-controller.ts"

---

## Test 6: Tool Use — Noisy Tool (view) — Should Be Silent

```powershell
$payload = @{
    timestamp  = "2026-01-01T00:00:00Z"
    cwd        = "."
    toolName   = "view"
    toolArgs   = '{"path":"src/auth-controller.ts"}'
    toolResult = @{ resultType = "success"; textResultForLlm = "File contents..." }
} | ConvertTo-Json -Compress

$payload | powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File ".github\hooks\scripts\on-post-tool-use.ps1"
```

**Expected**: **No audio** (silent exit). If you hear speech, check `voice-status-config.json` — "view" should be in `noisyTools`.

---

## Test 7: Tool Use — Bash with Test Output

```powershell
Remove-Item "$env:TEMP\voice-status-state.json" -Force -ErrorAction SilentlyContinue

$payload = @{
    timestamp  = "2026-01-01T00:00:00Z"
    cwd        = "."
    toolName   = "bash"
    toolArgs   = '{"command":"npm test"}'
    toolResult = @{ resultType = "success"; textResultForLlm = "15 tests passed, 2 tests failed" }
} | ConvertTo-Json -Compress

$payload | powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File ".github\hooks\scripts\on-post-tool-use.ps1"
```

**Expected speech**: "15 passed, 2 failed" (or similar summary)

---

## Test 8: Error Occurred

```powershell
# Note: errors bypass rate limiting — no need to reset state
$payload = @{
    timestamp = "2026-01-01T00:00:00Z"
    cwd       = "."
    error     = @{ name = "TimeoutError"; message = "Network timeout after 30 seconds"; stack = "" }
} | ConvertTo-Json -Compress

$payload | powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File ".github\hooks\scripts\on-error.ps1"
```

**Expected speech**: "Error: TimeoutError. Network timeout after 30 seconds"

---

## Test 9: Rate Limiting

Verify that a second message within 3 seconds is suppressed.

```powershell
# Reset state
Remove-Item "$env:TEMP\voice-status-state.json" -Force -ErrorAction SilentlyContinue

$startPayload = '{"timestamp":"2026-01-01T00:00:00Z","cwd":".","source":"new","initialPrompt":"First message"}'

# First invocation — should speak
$startPayload | powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File ".github\hooks\scripts\on-session-start.ps1"

# Immediately fire a second event — should be silent (within 3s rate limit)
'{"timestamp":"2026-01-01T00:00:00Z","cwd":".","reason":"complete"}' |
    powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File ".github\hooks\scripts\on-session-end.ps1"
```

**Expected**: First invocation speaks; second is **silent**.  
**Verify**: Wait 4 seconds and retry the second command — it should speak this time.

---

## Test 10: Deduplication

Verify that the same message within 10 seconds is suppressed.

```powershell
Remove-Item "$env:TEMP\voice-status-state.json" -Force -ErrorAction SilentlyContinue

$payload = '{"timestamp":"2026-01-01T00:00:00Z","cwd":".","source":"new","initialPrompt":"Deduplicated message"}'

# First — should speak
$payload | powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File ".github\hooks\scripts\on-session-start.ps1"

# Wait 4 seconds (past rate limit, but within dedup window)
Start-Sleep -Seconds 4

# Second — same payload, should be silent (dedup)
$payload | powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File ".github\hooks\scripts\on-session-start.ps1"
```

**Expected**: First speaks; second is **silent** (identical message within 10s window).

---

## Test 11: Error Bypasses Rate Limiting

Verify errors are always spoken even when the rate limit would otherwise suppress them.

```powershell
# Set state to "just spoke" — any normal hook would be rate limited
$now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
@{ lastSpokenAt = $now; recentMessages = @() } | ConvertTo-Json | Set-Content "$env:TEMP\voice-status-state.json"

# Now trigger an error — should still speak despite the rate limit
$errorPayload = @{
    timestamp = "2026-01-01T00:00:00Z"
    cwd       = "."
    error     = @{ name = "CriticalError"; message = "System failure detected"; stack = "" }
} | ConvertTo-Json -Compress

$errorPayload | powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File ".github\hooks\scripts\on-error.ps1"
```

**Expected speech**: "Error: CriticalError. System failure detected" — spoken immediately despite the rate limit.

---

## Test 12: Configuration Override via Environment Variable

```powershell
Remove-Item "$env:TEMP\voice-status-state.json" -Force -ErrorAction SilentlyContinue

# Reduce volume to 40%
$env:VOICE_STATUS_VOLUME = "40"

'{"timestamp":"2026-01-01T00:00:00Z","cwd":".","source":"new","initialPrompt":"Testing volume override"}' |
    powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File ".github\hooks\scripts\on-session-start.ps1"

# Restore
Remove-Item Env:VOICE_STATUS_VOLUME
```

**Expected**: Speech at noticeably lower volume.

---

## Test 13: End-to-End with Copilot CLI

This test verifies hooks fire live during an actual agent session.

1. Ensure `.github/hooks/voice-status.json` exists in your repo root
2. Start a Copilot CLI session:
   ```powershell
   cd your-repo
   gh copilot suggest "list the files in this directory"
   ```
3. **Expected**:
   - On session start: hear "Session started. list the files in this directory"
   - On tool completion: hear tool summary (if an interesting tool fires)
   - On session end: hear "Session complete"

---

## Running Pester Tests

Install Pester 5.x if not present:

```powershell
Install-Module -Name Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck
```

Run all unit and integration tests:

```powershell
cd your-repo
Invoke-Pester -Path tests\ -Output Detailed
```

Run a specific test file:

```powershell
Invoke-Pester -Path tests\voice-status-common.Tests.ps1 -Output Detailed
```

Run only sanitization tests:

```powershell
Invoke-Pester -Path tests\voice-status-common.Tests.ps1 -Output Detailed -TagFilter 'Sanitize'
```
