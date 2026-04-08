# test-helpers.ps1
# Shared Pester test utilities for voice-status hook tests
# Usage: . "$PSScriptRoot\test-helpers.ps1"

$script:CommonModule = Join-Path $PSScriptRoot "..\.github\hooks\scripts\voice-status-common.ps1"

function Get-CommonModulePath {
    # Resolve path to voice-status-common.ps1 relative to tests/
    return Resolve-Path (Join-Path $PSScriptRoot "..\.github\hooks\scripts\voice-status-common.ps1") -ErrorAction SilentlyContinue
}

function New-MockPayload {
    param([string]$EventType, [hashtable]$Overrides = @{})

    $ts = "2026-01-01T00:00:00.000Z"

    $base = switch ($EventType) {
        'sessionStart' {
            @{ timestamp = $ts; cwd = "C:\repo"; source = "new"; initialPrompt = "Fix the auth bug in login.ts" }
        }
        'sessionEnd' {
            @{ timestamp = $ts; cwd = "C:\repo"; reason = "complete" }
        }
        'userPromptSubmitted' {
            @{ timestamp = $ts; cwd = "C:\repo"; prompt = "Add unit tests for login" }
        }
        'postToolUse' {
            @{
                timestamp  = $ts
                cwd        = "C:\repo"
                toolName   = "edit"
                toolArgs   = '{"path":"src/auth.ts"}'
                toolResult = @{ resultType = "success"; textResultForLlm = "File updated successfully." }
            }
        }
        'errorOccurred' {
            @{
                timestamp = $ts
                cwd       = "C:\repo"
                error     = @{ name = "TimeoutError"; message = "Network timeout after 30s"; stack = "" }
            }
        }
        default { @{ timestamp = $ts; cwd = "C:\repo" } }
    }

    foreach ($key in $Overrides.Keys) { $base[$key] = $Overrides[$key] }
    return $base | ConvertTo-Json -Depth 10 -Compress
}

function Get-SampleToolResult {
    param([string]$Type = "success", [string]$Text = "")
    $map = @{
        success = @{ resultType = "success"; textResultForLlm = if ($Text) { $Text } else { "Operation completed." } }
        failure = @{ resultType = "failure"; textResultForLlm = if ($Text) { $Text } else { "Operation failed." } }
        denied  = @{ resultType = "denied";  textResultForLlm = "Permission denied." }
    }
    return [PSCustomObject]$map[$Type]
}

function New-TempStateFile {
    param([hashtable]$InitialState = @{})
    $path = Join-Path $env:TEMP "voice-status-state-test-$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).json"
    if ($InitialState.Count -gt 0) {
        $InitialState | ConvertTo-Json | Set-Content $path -Encoding UTF8
    }
    return $path
}

function Remove-TempStateFile {
    param([string]$Path)
    if ($Path -and (Test-Path $Path)) { Remove-Item $Path -Force -ErrorAction SilentlyContinue }
}

function Get-StateFileData {
    param([string]$Path = (Join-Path $env:TEMP "voice-status-state.json"))

    if (-not (Test-Path $Path)) { return $null }
    return Get-Content $Path -Raw | ConvertFrom-Json
}

function Get-RepoActivityFromStateFile {
    param(
        [string]$Path = (Join-Path $env:TEMP "voice-status-state.json"),
        [string]$Cwd = "C:\repo"
    )

    $state = Get-StateFileData -Path $Path
    if ($null -eq $state -or $null -eq $state.repoActivities) { return $null }

    $normalized = $Cwd.Trim().Replace('/', '\').ToLowerInvariant()
    foreach ($entry in @($state.repoActivities)) {
        if ($null -eq $entry) { continue }
        if ([string]::IsNullOrWhiteSpace([string]$entry.cwd)) { continue }
        if (($entry.cwd.ToString().Trim().Replace('/', '\').ToLowerInvariant()) -eq $normalized) {
            return $entry
        }
    }

    return $null
}

# Captures spoken messages without audio output for testing
$script:MockSpeechLog = [System.Collections.Generic.List[string]]::new()

function Reset-MockSpeechLog { $script:MockSpeechLog.Clear() }
function Get-MockSpeechLog   { return @($script:MockSpeechLog) }

function Invoke-MockSpeech {
    param([string]$Text, [hashtable]$Config)
    $script:MockSpeechLog.Add($Text)
}
