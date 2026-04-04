# on-session-start.ps1
# Hook: sessionStart — speaks a summary of the initial prompt
# Payload: { timestamp, cwd, source, initialPrompt }
param([string]$InputJson = '')

# When invoked by the hooks framework (powershell -File with piped stdin), no -InputJson is passed
# so we read from OpenStandardInput(). In Pester, callers pass -InputJson directly.
# We use $PSBoundParameters (not IsNullOrWhiteSpace) so that -InputJson '' doesn't fall through.
# IMPORTANT: Do NOT reference $input anywhere — its mere presence in a PS5.1 script
# causes the runtime to drain stdin before OpenStandardInput() can read it.
if (-not $PSBoundParameters.ContainsKey('InputJson')) {
    $InputJson = (New-Object System.IO.StreamReader([Console]::OpenStandardInput())).ReadToEnd()
}

. "$PSScriptRoot\voice-status-common.ps1"

$payload = Read-HookPayload -RawInput $InputJson
if ($null -eq $payload) { exit 0 }

$config = Get-VoiceStatusConfig

# Compose message
$prompt = if ($payload.initialPrompt) { [string]$payload.initialPrompt } else { '' }
if ($prompt.Length -gt 150) { $prompt = $prompt.Substring(0, 150) }

$message = if ($prompt) { "Session started. $prompt" } else { 'Session started' }
$message = Sanitize-TextForTTS -Text $message

if ([string]::IsNullOrWhiteSpace($message)) { exit 0 }

# Check rate limiting and deduplication
if (Test-RateLimited -Config $config) { exit 0 }
if (Test-IsDuplicate -Message $message -Config $config) { exit 0 }

# Speak and update state
Invoke-Speech -Text $message -Config $config
Update-SpeechState -SpokenAt ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -MessageHash (Get-MessageHash $message)

exit 0
