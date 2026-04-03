---
name: powershell-hook-testing
description: Patterns for testing Copilot hook PowerShell scripts with Pester — covering stdin/pipeline duality, TTS suppression, and injectable config paths.
---

# PowerShell Hook Script Testing

Copilot hook scripts receive JSON on **OS stdin** (when invoked by the hooks framework as a child process), but Pester tests use `$json | & script.ps1` which routes data through the **PowerShell pipeline** (`$input`). These are different streams. Getting this wrong causes tests to hang indefinitely.

## The Stdin/Pipeline Duality Pattern

### In `Read-HookPayload` (shared module)

```powershell
function Read-HookPayload {
    param(
        # When provided (e.g., from $input in a PS pipeline), use instead of [Console]::In.
        [string[]]$PipelineInput = $null
    )
    try {
        # CRITICAL: use $null -ne, NOT just $PipelineInput
        # @('') (empty string array) is falsy and would fall through to the blocking stdin read
        $raw = if ($null -ne $PipelineInput) {
            $PipelineInput -join [Environment]::NewLine
        } else {
            [Console]::In.ReadToEnd()   # production: hooks framework pipes OS stdin
        }
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return $raw | ConvertFrom-Json -ErrorAction Stop
    } catch { return $null }
}
```

### In each hook script

```powershell
# Pass $input (PS pipeline data) so tests work; production ignores it when null
$payload = Read-HookPayload -PipelineInput @($input)
```

### In Pester integration tests

```powershell
# This works because @($input) is not $null (even if $input is empty)
'{"key":"value"}' | & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-error.ps1")
$LASTEXITCODE | Should -Be 0
```

## TTS Suppression in Tests

`Invoke-Speech` spawns `Start-Job` background processes. Never let this run in tests.

```powershell
# In voice-status-common.ps1 Invoke-Speech:
if ($env:VOICE_STATUS_SKIP_TTS -eq '1') { return }

# In every integration test file's BeforeAll:
BeforeAll {
    . "$PSScriptRoot\test-helpers.ps1"
    . (Join-Path $PSScriptRoot "..\.github\hooks\scripts\voice-status-common.ps1")
    $env:VOICE_STATUS_SKIP_TTS = '1'
}
AfterAll { $env:VOICE_STATUS_SKIP_TTS = $null }
```

## Injectable Config Path (avoids mock fragility)

Don't mock `Test-Path`/`Get-Content` — it doesn't work reliably with dot-sourced code.
Add an injectable `$ConfigPath` parameter instead:

```powershell
# In Get-VoiceStatusConfig:
function Get-VoiceStatusConfig {
    param([string]$ConfigPath = (Join-Path $PSScriptRoot "voice-status-config.json"))
    ...
}

# In unit tests — use real temp files:
It 'loads values from JSON' {
    $cfg = Join-Path $env:TEMP "test-config.json"
    '{"rateLimitMs":5000}' | Set-Content $cfg
    try {
        $result = Get-VoiceStatusConfig -ConfigPath $cfg
        $result.rateLimitMs | Should -Be 5000
    } finally { Remove-Item $cfg -Force -ErrorAction SilentlyContinue }
}

# For "file not found" cases, pass a guaranteed nonexistent path:
$cfg = Get-VoiceStatusConfig -ConfigPath "C:\nonexistent\path\config.json"
```

## State File Isolation Between Tests

The rate limiter and dedup logic write to `$script:StateFile`. Tests should clean it:

```powershell
BeforeEach {
    $script:StateFile = Join-Path $env:TEMP "voice-status-state.json"
    Remove-Item $script:StateFile -Force -ErrorAction SilentlyContinue
}
```

Since the hook scripts set this to the same default path on load, the BeforeEach cleanup ensures each test starts with a clean state — even when the hook script under test is in a different scope.

## Learnings

- `$PipelineInput` must be checked with `$null -ne`, not truthy coercion — `@('')` is falsy but valid (it means "caller explicitly passed empty pipeline data, use PS path not OS stdin path").
- The `$PSScriptRoot` inside a dot-sourced function is the TEST FILE's directory, not the script's original directory. Default parameters like `Join-Path $PSScriptRoot "config.json"` in a function will resolve relative to the test file when dot-sourced in tests — another reason to prefer injectable paths.
