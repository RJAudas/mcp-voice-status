#!/usr/bin/env powershell
[CmdletBinding()]
param(
    [switch]$Watch,
    [string]$NodePath,
    [string]$DefaultCallSign,
    [string]$ConfigPath,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Resolve-NodePath {
    param([string]$ExplicitNodePath)

    $candidates = New-Object System.Collections.Generic.List[string]

    if ($ExplicitNodePath) {
        $candidates.Add($ExplicitNodePath)
    }

    $command = Get-Command node -ErrorAction SilentlyContinue
    if ($command -and $command.Source) {
        $candidates.Add($command.Source)
    }

    $registryCandidates = @(
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\node.exe'; Property = '(default)' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\node.exe'; Property = '(default)' },
        @{ Path = 'HKCU:\SOFTWARE\Node.js'; Property = 'InstallPath' },
        @{ Path = 'HKLM:\SOFTWARE\Node.js'; Property = 'InstallPath' },
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Node.js'; Property = 'InstallPath' }
    )

    foreach ($candidate in $registryCandidates) {
        if (-not (Test-Path -Path $candidate.Path)) {
            continue
        }

        $value = $null
        if ($candidate.Property -eq '(default)') {
            $registryKey = Get-Item -Path $candidate.Path -ErrorAction SilentlyContinue
            if ($registryKey) {
                $value = $registryKey.GetValue('')
            }
        } else {
            $itemProperties = Get-ItemProperty -Path $candidate.Path -ErrorAction SilentlyContinue
            if ($itemProperties -and $itemProperties.PSObject.Properties.Name -contains $candidate.Property) {
                $value = $itemProperties.$($candidate.Property)
            }
        }

        if ($value) {
            $candidates.Add($value)
        }
    }

    foreach ($pathCandidate in @(
        "$env:LOCALAPPDATA\Programs\nodejs\node.exe",
        "$env:ProgramFiles\nodejs\node.exe",
        "${env:ProgramFiles(x86)}\nodejs\node.exe"
    )) {
        if ($pathCandidate) {
            $candidates.Add($pathCandidate)
        }
    }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (Test-Path -Path $candidate -PathType Leaf) {
            return (Resolve-Path $candidate).Path
        }

        if (Test-Path -Path $candidate -PathType Container) {
            $nestedNodePath = Join-Path $candidate 'node.exe'
            if (Test-Path -Path $nestedNodePath -PathType Leaf) {
                return (Resolve-Path $nestedNodePath).Path
            }
        }
    }

    throw 'Unable to find node.exe. Install Node.js 20+ or pass -NodePath.'
}

function Assert-NodeVersion {
    param([string]$ResolvedNodePath)

    $versionText = & $ResolvedNodePath -p "process.versions.node"
    if ($LASTEXITCODE -ne 0 -or -not $versionText) {
        throw "Unable to determine the Node.js version from '$ResolvedNodePath'."
    }

    $majorVersion = [int](($versionText -split '\.')[0])
    if ($majorVersion -lt 20) {
        throw "Node.js 20+ is required. Found v$versionText at '$ResolvedNodePath'."
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tsxCliPath = Join-Path $repoRoot 'node_modules\tsx\dist\cli.mjs'
$entryPointPath = Join-Path $repoRoot 'src\index.ts'
$defaultConfigPath = Join-Path $repoRoot 'voice-status.config.json'

if (-not (Test-Path -Path $tsxCliPath -PathType Leaf)) {
    throw "Missing tsx runtime at '$tsxCliPath'. Run 'npm install' first."
}

if (-not (Test-Path -Path $entryPointPath -PathType Leaf)) {
    throw "Missing source entry point at '$entryPointPath'."
}

$resolvedNodePath = Resolve-NodePath -ExplicitNodePath $NodePath
Assert-NodeVersion -ResolvedNodePath $resolvedNodePath

$launchArgs = New-Object System.Collections.Generic.List[string]
$launchArgs.Add($tsxCliPath)

if ($Watch) {
    $launchArgs.Add('watch')
}

$launchArgs.Add($entryPointPath)

if ($DefaultCallSign) {
    $env:MCP_VOICE_DEFAULT_CALLSIGN = $DefaultCallSign
}

$resolvedConfigPath = $null
if ($ConfigPath) {
    $resolvedConfigPath = (Resolve-Path $ConfigPath).Path
} elseif (Test-Path -Path $defaultConfigPath -PathType Leaf) {
    $resolvedConfigPath = $defaultConfigPath
}

if ($resolvedConfigPath) {
    $env:MCP_VOICE_CONFIG_PATH = $resolvedConfigPath
}

if ($DryRun) {
    [PSCustomObject]@{
        RepoRoot = $repoRoot
        NodePath = $resolvedNodePath
        ConfigPath = $resolvedConfigPath
        EntryPoint = $entryPointPath
        TsxCliPath = $tsxCliPath
        Watch = [bool]$Watch
        Arguments = @($launchArgs)
    }
    exit 0
}

& $resolvedNodePath @launchArgs
exit $LASTEXITCODE
