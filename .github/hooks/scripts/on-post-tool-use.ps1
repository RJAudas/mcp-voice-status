# on-post-tool-use.ps1
# Hook: postToolUse — speaks tool completion summaries for interesting tools only
# Payload: { timestamp, cwd, tool_name, tool_input, tool_response }
param([string]$InputJson = '')

if (-not $PSBoundParameters.ContainsKey('InputJson')) {
    $InputJson = (New-Object System.IO.StreamReader([Console]::OpenStandardInput())).ReadToEnd()
}

. "$PSScriptRoot\voice-status-common.ps1"

$payload = Read-HookPayload -RawInput $InputJson
if ($null -eq $payload) { exit 0 }

$config = Get-VoiceStatusConfig

# Real payload uses snake_case fields
$toolName = if ($payload.tool_name)   { [string]$payload.tool_name }   else { '' }
$toolArgs = if ($payload.tool_input)  { $payload.tool_input | ConvertTo-Json -Compress -Depth 5 } else { '' }
$resultText = if ($payload.tool_response) { [string]$payload.tool_response } else { '' }
# Wrap into the shape Get-ToolSummary expects
$toolResult = [PSCustomObject]@{ resultType = 'success'; textResultForLlm = $resultText }

# Filter: only speak for interesting tools (US2 / FR-007, FR-008)
if (-not (Test-IsInterestingTool -ToolName $toolName -Config $config)) { exit 0 }

# Compose message
$message = Get-ToolSummary -ToolName $toolName -ToolArgs $toolArgs -ToolResult $toolResult
if ([string]::IsNullOrWhiteSpace($message)) { exit 0 }

$message = Sanitize-TextForTTS -Text $message
if ([string]::IsNullOrWhiteSpace($message)) { exit 0 }

if (Test-RateLimited -Config $config) { exit 0 }
if (Test-IsDuplicate -Message $message -Config $config) { exit 0 }

Invoke-Speech -Text $message -Config $config
Update-SpeechState -SpokenAt ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -MessageHash (Get-MessageHash $message)

exit 0
