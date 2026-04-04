---
description: Key learnings for the mcp-voice-status hooks architecture
---

# Project Learnings

## PowerShell Stdin Reading in Hook Scripts (PS5.1)

Hook scripts are invoked two ways:
1. **Production** (hooks framework): `powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File script.ps1` with JSON piped to stdin
2. **Pester tests**: `& script.ps1 -InputJson $json` (in-process, no stdin)

### The Solution: `param([string]$InputJson)` + `$PSBoundParameters`

Each hook script declares `param([string]$InputJson = '')` and uses `$PSBoundParameters.ContainsKey('InputJson')` to decide whether to read stdin:

```powershell
param([string]$InputJson = '')
if (-not $PSBoundParameters.ContainsKey('InputJson')) {
    $InputJson = (New-Object System.IO.StreamReader([Console]::OpenStandardInput())).ReadToEnd()
}
```

- **Production**: No `-InputJson` passed → reads raw stdin via `OpenStandardInput()`
- **Pester**: `-InputJson $json` passed → uses the parameter directly, never touches stdin

### Why Other Approaches Failed

| Approach | Failure Mode |
|----------|-------------|
| `@($input)` | Empty in PS5.1 `-File` mode — PS doesn't populate `$input` from piped stdin in child processes |
| `[Console]::In.ReadToEnd()` | Empty at script scope — PS preempts `Console.In` |
| `[Console]::OpenStandardInput()` alone | Blocks forever in Pester (interactive terminal, no EOF) |
| `if ([Console]::IsInputRedirected) { OpenStandardInput } else { @($input) }` | **Evaluating `IsInputRedirected` itself drains stdin in PS5.1** — both inline and block forms return empty |
| `IsNullOrWhiteSpace` guard on `$InputJson` | `-InputJson ''` (empty-string test) falls through to `OpenStandardInput()` which blocks |

### Key Insight

`$PSBoundParameters.ContainsKey('InputJson')` distinguishes "parameter not passed" (production) from "parameter passed as empty string" (Pester edge-case test).

## TTS: Fire-and-Forget via Start-Process

`Invoke-Speech` spawns a detached child process for TTS:

```powershell
Start-Process -FilePath "powershell" -ArgumentList "-NonInteractive -NoProfile -ExecutionPolicy Bypass -Command `"$cmd`"" -WindowStyle Hidden
```

- Uses synchronous `Speak()` (not `SpeakAsync`) in the child process
- `Start-Process` (not `Start-Job`) — jobs die when the parent exits
- `-WindowStyle Hidden` prevents a console window flash

## Pester Mocking of Dot-Sourced Cmdlets Is Unreliable

`Mock Test-Path` and `Mock Get-Content` applied in Pester tests do not reliably intercept calls made inside dot-sourced functions — the function's `$PSScriptRoot` and execution scope differ from the test scope. Instead:
- Add an optional injectable parameter (e.g., `$ConfigPath`) with a sensible default to functions that read files.
- In tests, pass a real temp file path directly rather than mocking.
- Tests are simpler, faster, and more accurate with real I/O over mocks for file operations.

## Integration Tests Must Suppress TTS

Hook scripts that call `Invoke-Speech` spawn `Start-Process` child processes for TTS. In a test session, these can cause noise. All integration test files must set `$env:VOICE_STATUS_SKIP_TTS = '1'` in their `BeforeAll` block and clear it in `AfterAll`. The `Invoke-Speech` function checks this flag and returns immediately without spawning any process.
