# on-session-start.ps1
# Hook: sessionStart — speaks a summary of the initial prompt
# Payload: { timestamp, cwd, source, initialPrompt }

. "$PSScriptRoot\voice-status-common.ps1"

$payload = Read-HookPayload -PipelineInput @($input)
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
