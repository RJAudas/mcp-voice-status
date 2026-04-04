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

$reasonMap = @{
    'complete'   = 'Session complete'
    'error'      = 'Session ended with error'
    'abort'      = 'Session aborted'
    'timeout'    = 'Session timed out'
    'user_exit'  = 'Session ended'
}

$reason  = if ($payload.reason) { [string]$payload.reason } else { 'complete' }
$message = if ($reasonMap.ContainsKey($reason)) { $reasonMap[$reason] } else { 'Session ended' }
$message = Sanitize-TextForTTS -Text $message

if ([string]::IsNullOrWhiteSpace($message)) { exit 0 }

if (Test-RateLimited -Config $config) { exit 0 }
if (Test-IsDuplicate -Message $message -Config $config) { exit 0 }

Invoke-Speech -Text $message -Config $config
Update-SpeechState -SpokenAt ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -MessageHash (Get-MessageHash $message)

exit 0
