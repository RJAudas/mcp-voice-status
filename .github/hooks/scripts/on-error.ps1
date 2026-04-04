# on-error.ps1
# Hook: errorOccurred — speaks error name and description, BYPASSES rate limiting (FR-009)
# Payload: { timestamp, cwd, error: { name, message, stack } }
param([string]$InputJson = '')

if (-not $PSBoundParameters.ContainsKey('InputJson')) {
    $InputJson = (New-Object System.IO.StreamReader([Console]::OpenStandardInput())).ReadToEnd()
}

. "$PSScriptRoot\voice-status-common.ps1"

$payload = Read-HookPayload -RawInput $InputJson
if ($null -eq $payload) { exit 0 }

$config = Get-VoiceStatusConfig

$errorName = if ($payload.error -and $payload.error.name)    { [string]$payload.error.name    } else { 'Error' }
$errorMsg  = if ($payload.error -and $payload.error.message) { [string]$payload.error.message } else { '' }

# Compose: "Error: [name]. [message]" within 200 char budget
$prefix  = "Error: $errorName."
$budget  = 200 - $prefix.Length - 1
$snippet = if ($errorMsg -and $budget -gt 0) { " " + $errorMsg.Substring(0, [Math]::Min($errorMsg.Length, $budget)) } else { '' }
$message = Sanitize-TextForTTS -Text ($prefix + $snippet)

if ([string]::IsNullOrWhiteSpace($message)) { exit 0 }

# Errors BYPASS rate limiting (per clarification / FR-009)
# Still check deduplication to avoid spamming repeated identical errors
if (Test-IsDuplicate -Message $message -Config $config) { exit 0 }

Invoke-Speech -Text $message -Config $config
Update-SpeechState -SpokenAt ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -MessageHash (Get-MessageHash $message)

exit 0
