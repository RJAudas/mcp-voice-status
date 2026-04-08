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

# Hook payloads vary between environments; support both snake_case and camelCase.
$cwd = if ($payload.cwd) { [string]$payload.cwd } else { '' }

$toolName = if ($payload.tool_name) {
    [string]$payload.tool_name
} elseif ($payload.toolName) {
    [string]$payload.toolName
} else {
    ''
}

$rawToolArgs = if ($payload.tool_input) {
    $payload.tool_input
} elseif ($payload.toolArgs) {
    $payload.toolArgs
} elseif ($payload.tool_args) {
    $payload.tool_args
} else {
    $null
}

$toolArgs = if ($rawToolArgs -is [string]) {
    [string]$rawToolArgs
} elseif ($null -ne $rawToolArgs) {
    $rawToolArgs | ConvertTo-Json -Compress -Depth 5
} else {
    ''
}

$toolResult = if ($payload.toolResult) {
    $payload.toolResult
} elseif ($payload.tool_result) {
    $payload.tool_result
} elseif ($payload.tool_response) {
    [PSCustomObject]@{ resultType = 'success'; textResultForLlm = [string]$payload.tool_response }
} else {
    [PSCustomObject]@{ resultType = 'success'; textResultForLlm = '' }
}

$resultType = Get-ToolResultType -ToolResult $toolResult

# Filter: only speak for interesting tools (US2 / FR-007, FR-008)
if (-not (Test-IsInterestingTool -ToolName $toolName -Config $config)) { exit 0 }

# Compose message
$message = Get-ToolSummary -ToolName $toolName -ToolArgs $toolArgs -ToolResult $toolResult
if ([string]::IsNullOrWhiteSpace($message)) { exit 0 }

$whySummary = Get-ToolIntent -ToolArgs $toolArgs
switch ($toolName) {
    { $_ -in @('edit', 'replace_string_in_file', 'multi_replace_string_in_file', 'create', 'create_file') } {
        Update-RepoActivity -Cwd $cwd -Milestone $message | Out-Null
    }
    default {
        Update-RepoActivity -Cwd $cwd -WhySummary $whySummary -Outcome $message | Out-Null
    }
}

$message = Sanitize-TextForTTS -Text $message
if ([string]::IsNullOrWhiteSpace($message)) { exit 0 }

if ($resultType -ne 'failure' -and (Test-RateLimited -Config $config)) { exit 0 }
if (Test-IsDuplicate -Message $message -Config $config) { exit 0 }

Invoke-Speech -Text $message -Config $config
Update-SpeechState -SpokenAt ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -MessageHash (Get-MessageHash $message)

exit 0
