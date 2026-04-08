#!/usr/bin/env powershell
[CmdletBinding()]
param(
    [ValidateSet('Workspace', 'User', 'Both')]
    [string]$VsCodeTarget = 'Workspace',
    [switch]$Watch,
    [string]$ServerName = 'voice-status',
    [string]$VsCodeUserConfigPath,
    [string]$CopilotConfigPath,
    [switch]$RefreshInstructions,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Ensure-ParentDirectory {
    param([string]$Path)

    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path -Path $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function ConvertTo-Hashtable {
    param([Parameter(ValueFromPipeline = $true)]$InputObject)

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $result[$key] = ConvertTo-Hashtable $InputObject[$key]
        }
        return $result
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in $InputObject) {
            $items.Add((ConvertTo-Hashtable $item))
        }
        return @($items)
    }

    if ($InputObject.PSObject -and $InputObject.PSObject.Properties.Count -gt 0) {
        $result = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-Hashtable $property.Value
        }
        return $result
    }

    return $InputObject
}

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        return $null
    }

    $rawContent = Get-Content -Path $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($rawContent)) {
        return $null
    }

    return ConvertTo-Hashtable ($rawContent | ConvertFrom-Json -Depth 100)
}

function Write-JsonFile {
    param(
        [string]$Path,
        [hashtable]$Content
    )

    Ensure-ParentDirectory -Path $Path
    $json = $Content | ConvertTo-Json -Depth 100
    Set-Content -Path $Path -Value ($json + [Environment]::NewLine) -Encoding UTF8
}

function Get-InstructionsTemplate {
    return @'
# Agent Instructions

## Voice Status

You have access to voice status tools. Use them to keep the user informed:

1. Before using voice status, check `voice-status.config.json` in the repo root if it exists and honor its `automation` settings.
2. At the start of a meaningful task, call `register_callsign` with the configured call sign (default: `"Copilot"`).
3. Use `speak_status` only for contextual callouts that help the user follow progress and outcome:
   - `confirm` when you start a meaningful task or hit a real milestone
   - `waiting` when you need user input
   - `blocked` when an external dependency or constraint is stopping progress
   - `done` when the task is complete; when there is a concrete result or answer, prefer speaking that concise result summary in the `done` callout instead of only saying the task is complete
   - `error` when something fails
4. Do **not** narrate every tool call, file read, or minor step unless the config explicitly allows low-value tool updates.
5. When completion and outcome narration are enabled, successful tasks should end with a `done` callout. Use a generic completion line only if the actual result cannot be stated clearly within the message limit.
6. Keep callouts factual, brief, and timely. Prefer silence over noisy commentary.

Keep spoken messages brief and under 200 characters.
'@
}

function Get-LaunchCommandArgs {
    param(
        [string]$LauncherPath,
        [bool]$EnableWatch
    )

    $args = New-Object System.Collections.Generic.List[string]
    $args.Add('-NoProfile')
    $args.Add('-ExecutionPolicy')
    $args.Add('Bypass')
    $args.Add('-File')
    $args.Add($LauncherPath)

    if ($EnableWatch) {
        $args.Add('-Watch')
    }

    return @($args)
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$launcherPath = (Resolve-Path (Join-Path $PSScriptRoot 'Start-VoiceMcpFromSource.ps1')).Path
$workspaceVsCodeConfigPath = Join-Path $repoRoot '.vscode\mcp.json'
$userVsCodeConfigPath = if ($VsCodeUserConfigPath) { $VsCodeUserConfigPath } else { Join-Path $env:APPDATA 'Code\User\mcp.json' }
$resolvedCopilotConfigPath = if ($CopilotConfigPath) { $CopilotConfigPath } else { Join-Path $HOME '.copilot\mcp-config.json' }
$instructionsPath = Join-Path $repoRoot '.github\copilot-instructions.md'
$instructionsTemplate = Get-InstructionsTemplate
$launchArgs = Get-LaunchCommandArgs -LauncherPath $launcherPath -EnableWatch $Watch.IsPresent

$vsCodeServer = [ordered]@{
    type = 'stdio'
    command = 'powershell.exe'
    args = @($launchArgs)
}

$copilotCliServer = [ordered]@{
    type = 'stdio'
    command = 'powershell.exe'
    args = @($launchArgs)
    env = [ordered]@{}
    tools = @('*')
}

$changes = New-Object System.Collections.Generic.List[string]

if ($VsCodeTarget -in @('Workspace', 'Both')) {
    $workspaceConfig = Read-JsonFile -Path $workspaceVsCodeConfigPath
    if ($null -eq $workspaceConfig) {
        $workspaceConfig = [ordered]@{}
    }
    if (-not $workspaceConfig.Contains('servers')) {
        $workspaceConfig['servers'] = [ordered]@{}
    }
    $workspaceConfig['servers'][$ServerName] = $vsCodeServer
    if (-not $DryRun) {
        Write-JsonFile -Path $workspaceVsCodeConfigPath -Content $workspaceConfig
    }
    $changes.Add("VS Code workspace MCP config -> $workspaceVsCodeConfigPath")
}

if ($VsCodeTarget -in @('User', 'Both')) {
    $userConfig = Read-JsonFile -Path $userVsCodeConfigPath
    if ($null -eq $userConfig) {
        $userConfig = [ordered]@{}
    }
    if (-not $userConfig.Contains('servers')) {
        $userConfig['servers'] = [ordered]@{}
    }
    $userConfig['servers'][$ServerName] = $vsCodeServer
    if (-not $DryRun) {
        Write-JsonFile -Path $userVsCodeConfigPath -Content $userConfig
    }
    $changes.Add("VS Code user MCP config -> $userVsCodeConfigPath")
}

$copilotConfig = Read-JsonFile -Path $resolvedCopilotConfigPath
if ($null -eq $copilotConfig) {
    $copilotConfig = [ordered]@{}
}
if (-not $copilotConfig.Contains('mcpServers')) {
    $copilotConfig['mcpServers'] = [ordered]@{}
}
$copilotConfig['mcpServers'][$ServerName] = $copilotCliServer
if (-not $DryRun) {
    Write-JsonFile -Path $resolvedCopilotConfigPath -Content $copilotConfig
}
$changes.Add("Copilot CLI MCP config -> $resolvedCopilotConfigPath")

$shouldWriteInstructions = $RefreshInstructions -or -not (Test-Path -Path $instructionsPath -PathType Leaf)
if ($shouldWriteInstructions -and -not $DryRun) {
    Ensure-ParentDirectory -Path $instructionsPath
    Set-Content -Path $instructionsPath -Value ($instructionsTemplate + [Environment]::NewLine) -Encoding UTF8
}
if ($shouldWriteInstructions) {
    $changes.Add("Copilot instructions -> $instructionsPath")
}

[PSCustomObject]@{
    RepoRoot = $repoRoot
    ServerName = $ServerName
    VsCodeTarget = $VsCodeTarget
    Watch = [bool]$Watch
    LauncherPath = $launcherPath
    Updated = @($changes)
    InstructionsWritten = [bool]$shouldWriteInstructions
}
