# on-prompt-submitted.ps1
# Hook: userPromptSubmitted — speaks a brief summary of the new instruction
# Payload: { timestamp, cwd, prompt }

. "$PSScriptRoot\voice-status-common.ps1"

$payload = Read-HookPayload -PipelineInput @($input)
if ($null -eq $payload) { exit 0 }

$config = Get-VoiceStatusConfig

$prompt = if ($payload.prompt) { [string]$payload.prompt } else { '' }
if ([string]::IsNullOrWhiteSpace($prompt)) { exit 0 }

# "New task: " prefix = 10 chars; leave ~180 for the prompt
$prefix    = 'New task: '
$maxPrompt = 200 - $prefix.Length
if ($prompt.Length -gt $maxPrompt) { $prompt = $prompt.Substring(0, $maxPrompt) }

$message = Sanitize-TextForTTS -Text ($prefix + $prompt)
if ([string]::IsNullOrWhiteSpace($message)) { exit 0 }

if (Test-RateLimited -Config $config) { exit 0 }
if (Test-IsDuplicate -Message $message -Config $config) { exit 0 }

Invoke-Speech -Text $message -Config $config
Update-SpeechState -SpokenAt ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -MessageHash (Get-MessageHash $message)

exit 0
