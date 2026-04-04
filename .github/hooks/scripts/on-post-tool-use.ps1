# on-post-tool-use.ps1
# Hook: postToolUse — speaks tool completion summaries for interesting tools only
# Payload: { timestamp, cwd, toolName, toolArgs, toolResult: { resultType, textResultForLlm } }
param([string]$InputJson = '')

if (-not $PSBoundParameters.ContainsKey('InputJson')) {
    $InputJson = (New-Object System.IO.StreamReader([Console]::OpenStandardInput())).ReadToEnd()
}

. "$PSScriptRoot\voice-status-common.ps1"

$payload = Read-HookPayload -RawInput $rawStdin
if ($null -eq $payload) { exit 0 }

$config   = Get-VoiceStatusConfig
$toolName = if ($payload.toolName) { [string]$payload.toolName } else { '' }

# Filter: only speak for interesting tools (US2 / FR-007, FR-008)
if (-not (Test-IsInterestingTool -ToolName $toolName -Config $config)) { exit 0 }

# Build tool result object
$toolResult = $payload.toolResult

# Compose message
$message = Get-ToolSummary -ToolName $toolName -ToolArgs ([string]$payload.toolArgs) -ToolResult $toolResult
if ([string]::IsNullOrWhiteSpace($message)) { exit 0 }

$message = Sanitize-TextForTTS -Text $message
if ([string]::IsNullOrWhiteSpace($message)) { exit 0 }

# Failures bypass rate limiting (FR-009, US4)
$isFailure = ($toolResult -and [string]$toolResult.resultType -eq 'failure')

if (-not $isFailure) {
    if (Test-RateLimited -Config $config) { exit 0 }
}
if (Test-IsDuplicate -Message $message -Config $config) { exit 0 }

Invoke-Speech -Text $message -Config $config
Update-SpeechState -SpokenAt ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -MessageHash (Get-MessageHash $message)

exit 0
