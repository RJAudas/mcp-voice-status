# on-session-end.ps1
# Hook: sessionEnd — speaks the completion reason
# Payload: { timestamp, cwd, reason }
param([string]$InputJson = '')

if (-not $PSBoundParameters.ContainsKey('InputJson')) {
    $InputJson = (New-Object System.IO.StreamReader([Console]::OpenStandardInput())).ReadToEnd()
}

. "$PSScriptRoot\voice-status-common.ps1"

$payload = Read-HookPayload -RawInput $InputJson
if ($null -eq $payload) { exit 0 }

$config = Get-VoiceStatusConfig

$cwd     = if ($payload.cwd) { [string]$payload.cwd } else { '' }
$reason  = if ($payload.reason) { [string]$payload.reason } else { 'complete' }
$message = Build-SessionRecap -Cwd $cwd -Reason $reason

if ([string]::IsNullOrWhiteSpace($message)) { exit 0 }

if (Test-IsDuplicate -Message $message -Config $config) {
    Clear-RepoActivity -Cwd $cwd
    exit 0
}

Invoke-Speech -Text $message -Config $config
Update-SpeechState -SpokenAt ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -MessageHash (Get-MessageHash $message)
Clear-RepoActivity -Cwd $cwd

exit 0
