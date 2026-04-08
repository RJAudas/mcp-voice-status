# on-prompt-submitted.ps1
# Hook: userPromptSubmitted — speaks a brief summary of the new instruction
# Payload: { timestamp, cwd, prompt }
param([string]$InputJson = '')

if (-not $PSBoundParameters.ContainsKey('InputJson')) {
    $InputJson = (New-Object System.IO.StreamReader([Console]::OpenStandardInput())).ReadToEnd()
}

. "$PSScriptRoot\voice-status-common.ps1"

$payload = Read-HookPayload -RawInput $InputJson
if ($null -eq $payload) { exit 0 }

$config = Get-VoiceStatusConfig

$cwd    = if ($payload.cwd) { [string]$payload.cwd } else { '' }
$prompt = if ($payload.prompt) { Limit-ContextText -Text ([string]$payload.prompt) -MaxLength 110 } else { '' }
if ([string]::IsNullOrWhiteSpace($prompt)) { exit 0 }

Update-RepoActivity -Cwd $cwd -TaskSummary $prompt -Reset | Out-Null

$message = Sanitize-TextForTTS -Text ("Now working on: " + $prompt)
if ([string]::IsNullOrWhiteSpace($message)) { exit 0 }

if (Test-RateLimited -Config $config) { exit 0 }
if (Test-IsDuplicate -Message $message -Config $config) { exit 0 }

Invoke-Speech -Text $message -Config $config
Update-SpeechState -SpokenAt ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -MessageHash (Get-MessageHash $message)

exit 0
