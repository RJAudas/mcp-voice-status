---
description: Key learnings for the mcp-voice-status hooks architecture
---

# Project Learnings

## PowerShell Pipeline vs OS Stdin in Hook Scripts

When testing hook scripts with `$json | & script.ps1` in Pester, `[Console]::In.ReadToEnd()` **blocks** — it reads OS-level stdin (the interactive terminal), not the PowerShell pipeline. The PS pipeline populates `$input` in the script scope, not `[Console]::In`. Fix: `Read-HookPayload` accepts an optional `[string[]]$PipelineInput` parameter; hook scripts pass `@($input)` when calling it. The fallback to `[Console]::In.ReadToEnd()` is used only in production (hooks framework spawns a real child process with OS stdin). The null check **must** be `if ($null -ne $PipelineInput)`, not `if ($PipelineInput)`, because `@('')` (empty string array) is falsy in PowerShell and would incorrectly fall through to the blocking stdin read.

## Pester Mocking of Dot-Sourced Cmdlets Is Unreliable

`Mock Test-Path` and `Mock Get-Content` applied in Pester tests do not reliably intercept calls made inside dot-sourced functions — the function's `$PSScriptRoot` and execution scope differ from the test scope. Instead:
- Add an optional injectable parameter (e.g., `$ConfigPath`) with a sensible default to functions that read files.
- In tests, pass a real temp file path directly rather than mocking.
- Tests are simpler, faster, and more accurate with real I/O over mocks for file operations.

## Integration Tests Must Suppress TTS

Hook scripts that call `Invoke-Speech` spin up `Start-Job` background jobs. In a test session, these accumulate and can cause noise, slowness, or unexpected behavior. All integration test files must set `$env:VOICE_STATUS_SKIP_TTS = '1'` in their `BeforeAll` block and clear it in `AfterAll`. The `Invoke-Speech` function checks this flag and returns immediately without spawning any job.
