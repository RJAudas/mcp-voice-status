# voice-status-common.ps1
# Shared module: TTS, sanitization, rate limiting, deduplication, config loading
# Dot-source this file in all hook scripts: . "$PSScriptRoot\voice-status-common.ps1"

#region Config Loading (T006)

$script:DefaultConfig = @{
    interestingTools = @("edit", "create", "bash", "powershell", "write_powershell", "task")
    noisyTools       = @("view", "grep", "glob", "read_powershell", "list_powershell", "web_fetch")
    rateLimitMs      = 3000
    dedupWindowMs    = 10000
    ttsTimeoutMs     = 30000
    voiceRate        = 0
    voiceVolume      = 100
}

function Get-VoiceStatusConfig {
    param([string]$ConfigPath = (Join-Path $PSScriptRoot "voice-status-config.json"))

    $config = $script:DefaultConfig.Clone()

    # Try to load JSON config
    if (Test-Path $ConfigPath) {
        try {
            $json = Get-Content $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($null -ne $json.interestingTools) { $config.interestingTools = @($json.interestingTools) }
            if ($null -ne $json.noisyTools)       { $config.noisyTools       = @($json.noisyTools) }
            if ($null -ne $json.rateLimitMs)      { $config.rateLimitMs      = [int]$json.rateLimitMs }
            if ($null -ne $json.dedupWindowMs)    { $config.dedupWindowMs    = [int]$json.dedupWindowMs }
            if ($null -ne $json.ttsTimeoutMs)     { $config.ttsTimeoutMs     = [int]$json.ttsTimeoutMs }
            if ($null -ne $json.voiceRate)        { $config.voiceRate        = [int]$json.voiceRate }
            if ($null -ne $json.voiceVolume)      { $config.voiceVolume      = [int]$json.voiceVolume }
        } catch { <# Malformed JSON — use defaults #> }
    }

    # Apply env var overrides (string-to-int; fall back to current value on failure)
    $envMap = @{
        VOICE_STATUS_RATE_LIMIT_MS  = 'rateLimitMs'
        VOICE_STATUS_DEDUP_WINDOW_MS = 'dedupWindowMs'
        VOICE_STATUS_TIMEOUT_MS     = 'ttsTimeoutMs'
        VOICE_STATUS_VOLUME         = 'voiceVolume'
        VOICE_STATUS_RATE           = 'voiceRate'
    }
    foreach ($envVar in $envMap.Keys) {
        $envVal = [System.Environment]::GetEnvironmentVariable($envVar)
        if (-not [string]::IsNullOrWhiteSpace($envVal)) {
            $parsed = 0
            if ([int]::TryParse($envVal.Trim(), [ref]$parsed)) {
                $config[$envMap[$envVar]] = $parsed
            }
        }
    }

    # Basic range clamping
    if ($config.rateLimitMs   -lt 1000)  { $config.rateLimitMs   = 1000 }
    if ($config.dedupWindowMs -lt 1000)  { $config.dedupWindowMs = 1000 }
    if ($config.ttsTimeoutMs  -lt 5000)  { $config.ttsTimeoutMs  = 5000 }
    if ($config.voiceVolume   -lt 0)     { $config.voiceVolume   = 0 }
    if ($config.voiceVolume   -gt 100)   { $config.voiceVolume   = 100 }
    if ($config.voiceRate     -lt -10)   { $config.voiceRate     = -10 }
    if ($config.voiceRate     -gt 10)    { $config.voiceRate     = 10 }

    return $config
}

#endregion

#region Text Sanitization (T007)

function Sanitize-TextForTTS {
    param([string]$Text, [int]$MaxLength = 200)

    if ([string]::IsNullOrEmpty($Text)) { return '' }

    # Remove null bytes
    $Text = $Text -replace "`0", ' '

    # Strip SSML/XML tags
    $Text = $Text -replace '<[^>]*>', ' '

    # Remove double quotes (prevent PS string boundary breaks)
    $Text = $Text -replace '"', ''

    # Remove backticks (PS escape character)
    $Text = $Text -replace '`', ''

    # Escape single quotes by doubling them (safe for PS string embedding)
    $Text = $Text -replace "'", "''"

    # Strip control characters except tab, newline, CR
    $Text = $Text -replace '[^\x09\x0A\x0D\x20-\x7E\x80-\xFF]', ' '

    # Collapse whitespace (including tabs, newlines) to single space
    $Text = $Text -replace '\s+', ' '

    # Trim
    $Text = $Text.Trim()

    # Enforce max length
    if ($Text.Length -gt $MaxLength) {
        $Text = $Text.Substring(0, $MaxLength).TrimEnd()
    }

    return $Text
}

#endregion

function Limit-ContextText {
    param([string]$Text, [int]$MaxLength = 120)

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }

    $normalized = ($Text -replace '\s+', ' ').Trim()
    if ($normalized.Length -gt $MaxLength) {
        return $normalized.Substring(0, $MaxLength).TrimEnd()
    }

    return $normalized
}

#region Fire-and-Forget TTS (T008)

function Invoke-Speech {
    param(
        [string]$Text,
        [hashtable]$Config
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return }

    # Skip actual TTS when VOICE_STATUS_SKIP_TTS=1 (for testing/CI)
    if ($env:VOICE_STATUS_SKIP_TTS -eq '1') { return }

    $rate    = $Config.voiceRate
    $volume  = $Config.voiceVolume

    # Fire-and-forget: launch a detached powershell.exe with inline TTS command.
    # Using -Command instead of -File avoids temp file creation and stdin interference.
    $cmd = "Add-Type -AssemblyName System.Speech; " +
           "`$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; " +
           "`$s.Rate = $rate; " +
           "`$s.Volume = $volume; " +
           "`$s.Speak('$Text'); " +
           "`$s.Dispose()"

    Start-Process -FilePath "powershell" `
        -ArgumentList "-NonInteractive -NoProfile -ExecutionPolicy Bypass -Command `"$cmd`"" `
        -WindowStyle Hidden
}

#endregion

#region Stdin JSON Parser (T009)

function Read-HookPayload {
    param(
        # Raw stdin string, read at script scope before any function calls.
        # Console.In is empty inside functions (PS buffers stdin for $input on function entry).
        # Each hook script reads stdin at the top level and passes it here.
        [string]$RawInput = ''
    )
    try {
        if ([string]::IsNullOrWhiteSpace($RawInput)) { return $null }
        return $RawInput | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $null
    }
}

#endregion

#region Message Summarization (T010)

function Get-ToolSummary {
    param(
        [string]$ToolName,
        [string]$ToolArgs,
        [object]$ToolResult
    )

    $resultText = Get-ToolResultText -ToolResult $ToolResult
    $resultType = Get-ToolResultType -ToolResult $ToolResult

    switch ($ToolName) {
        { $_ -in @('edit', 'replace_string_in_file', 'multi_replace_string_in_file') } {
            $filename = Get-FilenameFromArgs $ToolArgs
            if ($filename) { return "Edited $filename" }
            return 'File edited'
        }
        { $_ -in @('create', 'create_file') } {
            $filename = Get-FilenameFromArgs $ToolArgs
            if ($filename) { return "Created $filename" }
            return 'File created'
        }
        { $_ -in @('bash', 'powershell', 'write_powershell', 'run_in_terminal', 'task') } {
            return Get-CommandSummary -Output $resultText -ToolArgs $ToolArgs -ResultType $resultType
        }
        default {
            return $null  # Unknown/uninteresting — silent skip
        }
    }
}

function Get-ToolResultText {
    param([object]$ToolResult)

    if ($null -eq $ToolResult) { return '' }
    if ($ToolResult -is [string]) { return [string]$ToolResult }

    foreach ($propertyName in @('textResultForLlm', 'tool_response', 'output', 'message')) {
        $property = $ToolResult.PSObject.Properties[$propertyName]
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            return [string]$property.Value
        }
    }

    return ''
}

function Get-ToolResultType {
    param([object]$ToolResult)

    if ($null -eq $ToolResult) { return 'success' }
    if ($ToolResult -is [string]) { return 'success' }

    $property = $ToolResult.PSObject.Properties['resultType']
    if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
        return ([string]$property.Value).ToLowerInvariant()
    }

    return 'success'
}

function Get-FilenameFromArgs {
    param([string]$ToolArgs)
    if ([string]::IsNullOrWhiteSpace($ToolArgs)) { return $null }
    try {
        $parsedArgs = $ToolArgs | ConvertFrom-Json -ErrorAction Stop
        # Try common field names for file path
        $path = $null
        foreach ($propertyName in @('filePath', 'path', 'file_path', 'filename', 'target_file')) {
            $property = $parsedArgs.PSObject.Properties[$propertyName]
            if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                $path = [string]$property.Value
                break
            }
        }
        if ($path) { return [System.IO.Path]::GetFileName($path) }
    } catch { }
    return $null
}

function Get-CommandSummary {
    param([string]$Output, [string]$ToolArgs, [string]$ResultType = 'success')

    $why = Get-ToolIntent -ToolArgs $ToolArgs
    $resultSummary = Get-OutputResultSummary -Output $Output

    if ($resultSummary) {
        if ($why) { return "$why. $resultSummary" }
        return $resultSummary
    }

    if ($ResultType -eq 'failure') {
        if ($why) { return "$why failed" }
        if (-not [string]::IsNullOrWhiteSpace($Output)) { return Limit-ContextText -Text $Output -MaxLength 120 }
        return 'Command failed'
    }

    if ($why) { return $why }
    return $null
}

function Get-ToolIntent {
    param([string]$ToolArgs)

    if ([string]::IsNullOrWhiteSpace($ToolArgs)) { return $null }

    try {
        $parsedArgs = $ToolArgs | ConvertFrom-Json -ErrorAction Stop
        foreach ($propertyName in @('goal', 'explanation', 'description', 'summary', 'intent')) {
            $property = $parsedArgs.PSObject.Properties[$propertyName]
            if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                return Limit-ContextText -Text ([string]$property.Value) -MaxLength 100
            }
        }
    } catch { }

    return $null
}

# Extract a structured result summary from command output (test/build/lint patterns).
# Returns $null if no pattern matches — callers fall back to goal/explanation or generic message.
function Get-OutputResultSummary {
    param([string]$Output)
    if ([string]::IsNullOrWhiteSpace($Output)) { return $null }

    $o = $Output.ToLower()

    # Pester 5 format: "Tests Passed: 15, Failed: 0, Skipped: 0 NotRun: 0"
    if ($o -match 'tests\s+passed:\s*(\d+)') {
        $passed = $Matches[1]
        if ($o -match 'failed:\s*(\d+)' -and [int]$Matches[1] -gt 0) {
            return "$passed passed, $($Matches[1]) failed"
        }
        return "$passed tests passed"
    }

    # Generic xUnit / Mocha / Jest style: "15 tests passed", "15 passing"
    if ($o -match '(\d+)\s+(?:tests?|specs?|examples?)\s+passed' -or
        $o -match 'all\s+(\d+)\s+(?:tests?|specs?)\s+passed' -or
        $o -match '(\d+)\s+passing') {
        $passed = $Matches[1]
        if ($o -match '(\d+)\s+(?:tests?|specs?|examples?)\s+failed' -or $o -match '(\d+)\s+failing') {
            return "$passed passed, $($Matches[1]) failed"
        }
        return "$passed tests passed"
    }
    if ($o -match '(\d+)\s+(?:tests?|specs?|examples?)\s+failed' -or $o -match '(\d+)\s+failing') {
        return "$($Matches[1]) tests failed"
    }

    if ($o -match 'build\s+succeeded' -or $o -match 'build\s+success') { return 'Build succeeded' }
    if ($o -match 'build\s+failed' -or $o -match 'build\s+error') { return 'Build failed' }
    if ($o -match '(\d+)\s+errors?,\s*(\d+)\s+warnings?') {
        $e = $Matches[1]; $w = $Matches[2]
        if ($e -eq '0' -and $w -eq '0') { return 'Lint passed' }
        if ($e -eq '0') { return "Lint: $w warnings" }
        return "Lint: $e errors, $w warnings"
    }
    return $null
}

#endregion

#region Tool Classification (T023)

function Test-IsInterestingTool {
    param([string]$ToolName, [hashtable]$Config)
    return $Config.interestingTools -contains $ToolName
}

#endregion

#region Rate Limiting & Deduplication (T028, T029)

$script:StateFile = Join-Path $env:TEMP "voice-status-state.json"

function New-VoiceState {
    return [PSCustomObject]@{
        lastSpokenAt   = 0
        recentMessages = @()
        repoActivities = @()
    }
}

function New-RepoActivity {
    param([string]$Cwd = '')

    return [PSCustomObject]@{
        cwd           = $Cwd
        taskSummary   = ''
        whySummary    = ''
        milestones    = @()
        latestOutcome = ''
        lastReason    = ''
        lastUpdatedAt = 0
    }
}

function Get-StateData {
    $state = $null

    try {
        if (Test-Path $script:StateFile) {
            $raw = Get-Content $script:StateFile -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $state = $raw | ConvertFrom-Json -ErrorAction Stop
            }
        }
    } catch {
        $state = $null
    }

    if ($null -eq $state) {
        return New-VoiceState
    }

    if ($null -eq $state.PSObject.Properties['lastSpokenAt']) {
        $state | Add-Member -NotePropertyName 'lastSpokenAt' -NotePropertyValue 0
    }
    if ($null -eq $state.PSObject.Properties['recentMessages']) {
        $state | Add-Member -NotePropertyName 'recentMessages' -NotePropertyValue @()
    }
    if ($null -eq $state.PSObject.Properties['repoActivities']) {
        $state | Add-Member -NotePropertyName 'repoActivities' -NotePropertyValue @()
    }

    return $state
}

function Save-StateData {
    param([object]$State)

    $tmp = $script:StateFile + ".tmp"
    try {
        $State | ConvertTo-Json -Compress -Depth 10 | Set-Content -Path $tmp -Encoding UTF8 -ErrorAction Stop
        Move-Item -Path $tmp -Destination $script:StateFile -Force -ErrorAction Stop
    } catch {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Normalize-RepoPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return $Path.Trim().Replace('/', '\').ToLowerInvariant()
}

function Test-IsSameRepoPath {
    param([string]$Left, [string]$Right)

    return (Normalize-RepoPath -Path $Left) -eq (Normalize-RepoPath -Path $Right)
}

function Add-UniqueSummaryText {
    param([object[]]$Existing, [string]$NewText, [int]$MaxItems = 3)

    $text = Limit-ContextText -Text $NewText -MaxLength 100
    if ([string]::IsNullOrWhiteSpace($text)) { return @($Existing) }

    $items = [System.Collections.Generic.List[string]]::new()
    foreach ($item in @($Existing)) {
        $value = [string]$item
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        if ($value.ToLowerInvariant() -eq $text.ToLowerInvariant()) { continue }
        $items.Add($value)
    }

    $items.Add($text)
    while ($items.Count -gt $MaxItems) {
        $items.RemoveAt(0)
    }

    return @($items)
}

function Get-RepoActivity {
    param([string]$Cwd)

    $state = Get-StateData
    foreach ($entry in @($state.repoActivities)) {
        if ($null -eq $entry) { continue }
        if (Test-IsSameRepoPath -Left ([string]$entry.cwd) -Right $Cwd) {
            if ($null -eq $entry.PSObject.Properties['taskSummary']) {
                $entry | Add-Member -NotePropertyName 'taskSummary' -NotePropertyValue ''
            }
            if ($null -eq $entry.PSObject.Properties['whySummary']) {
                $entry | Add-Member -NotePropertyName 'whySummary' -NotePropertyValue ''
            }
            if ($null -eq $entry.PSObject.Properties['milestones']) {
                $entry | Add-Member -NotePropertyName 'milestones' -NotePropertyValue @()
            }
            if ($null -eq $entry.PSObject.Properties['latestOutcome']) {
                $entry | Add-Member -NotePropertyName 'latestOutcome' -NotePropertyValue ''
            }
            if ($null -eq $entry.PSObject.Properties['lastReason']) {
                $entry | Add-Member -NotePropertyName 'lastReason' -NotePropertyValue ''
            }
            if ($null -eq $entry.PSObject.Properties['lastUpdatedAt']) {
                $entry | Add-Member -NotePropertyName 'lastUpdatedAt' -NotePropertyValue 0
            }
            return $entry
        }
    }

    return New-RepoActivity -Cwd $Cwd
}

function Update-RepoActivity {
    param(
        [string]$Cwd,
        [string]$TaskSummary = '',
        [string]$WhySummary = '',
        [string]$Milestone = '',
        [string]$Outcome = '',
        [string]$LastReason = '',
        [switch]$Reset
    )

    $state = Get-StateData
    $activity = if ($Reset) { New-RepoActivity -Cwd $Cwd } else { Get-RepoActivity -Cwd $Cwd }

    if (-not [string]::IsNullOrWhiteSpace($TaskSummary)) {
        $activity.taskSummary = Limit-ContextText -Text $TaskSummary -MaxLength 110
    }
    if (-not [string]::IsNullOrWhiteSpace($WhySummary)) {
        $activity.whySummary = Limit-ContextText -Text $WhySummary -MaxLength 100
    }
    if (-not [string]::IsNullOrWhiteSpace($Milestone)) {
        $activity.milestones = Add-UniqueSummaryText -Existing @($activity.milestones) -NewText $Milestone -MaxItems 3
    }
    if (-not [string]::IsNullOrWhiteSpace($Outcome)) {
        $activity.latestOutcome = Limit-ContextText -Text $Outcome -MaxLength 100
    }
    if (-not [string]::IsNullOrWhiteSpace($LastReason)) {
        $activity.lastReason = $LastReason
    }
    $activity.lastUpdatedAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

    $updatedActivities = [System.Collections.Generic.List[object]]::new()
    $replaced = $false
    foreach ($entry in @($state.repoActivities)) {
        if ($null -eq $entry) { continue }
        if (-not $replaced -and (Test-IsSameRepoPath -Left ([string]$entry.cwd) -Right $Cwd)) {
            $updatedActivities.Add($activity)
            $replaced = $true
            continue
        }
        $updatedActivities.Add($entry)
    }
    if (-not $replaced) {
        $updatedActivities.Add($activity)
    }

    $state.repoActivities = @($updatedActivities)
    Save-StateData -State $state

    return $activity
}

function Clear-RepoActivity {
    param([string]$Cwd)

    if ([string]::IsNullOrWhiteSpace($Cwd)) { return }

    $state = Get-StateData
    $remaining = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($state.repoActivities)) {
        if ($null -eq $entry) { continue }
        if (Test-IsSameRepoPath -Left ([string]$entry.cwd) -Right $Cwd) { continue }
        $remaining.Add($entry)
    }

    $state.repoActivities = @($remaining)
    Save-StateData -State $state
}

function Get-SpeechState {
    return Get-StateData
}

function Update-SpeechState {
    param([long]$SpokenAt, [string]$MessageHash)
    $state = Get-SpeechState
    $state.lastSpokenAt = $SpokenAt

    # Add new message hash
    $entry = [PSCustomObject]@{ hash = $MessageHash; spokenAt = $SpokenAt }
    $messages = @($state.recentMessages) + $entry

    # Prune expired entries (keep only within dedupWindowMs — use max window for safety)
    $windowMs = 300000  # 5 minutes max keep
    $cutoff   = $SpokenAt - $windowMs
    $messages = $messages | Where-Object { $_.spokenAt -gt $cutoff }

    $state.recentMessages = $messages
    Save-StateData -State $state
}

function Test-RateLimited {
    param([hashtable]$Config)
    try {
        $state = Get-SpeechState
        $now   = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $delta = $now - [long]$state.lastSpokenAt
        return $delta -lt $Config.rateLimitMs
    } catch {
        return $false
    }
}

function Test-IsDuplicate {
    param([string]$Message, [hashtable]$Config)
    try {
        $hash  = Get-MessageHash $Message
        $state = Get-SpeechState
        $now   = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $cutoff = $now - $Config.dedupWindowMs

        # Prune expired, then check
        foreach ($entry in $state.recentMessages) {
            if ($entry.hash -eq $hash -and [long]$entry.spokenAt -gt $cutoff) {
                return $true
            }
        }
        return $false
    } catch {
        return $false
    }
}

function Get-MessageHash {
    param([string]$Message)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Message.ToLower().Trim())
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    $hash  = $sha.ComputeHash($bytes)
    $sha.Dispose()
    return [System.BitConverter]::ToString($hash).Replace('-', '').Substring(0, 16)
}

function Add-RecapPart {
    param([System.Collections.Generic.List[string]]$Parts, [string]$Text)

    $candidate = Limit-ContextText -Text $Text -MaxLength 100
    if ([string]::IsNullOrWhiteSpace($candidate)) { return }

    foreach ($existing in $Parts) {
        if ($existing.ToLowerInvariant() -eq $candidate.ToLowerInvariant()) {
            return
        }
    }

    $Parts.Add($candidate)
}

function Build-SessionRecap {
    param([string]$Cwd, [string]$Reason = 'complete')

    $fallbackMap = @{
        'complete'  = 'Session complete'
        'error'     = 'Session ended with error'
        'abort'     = 'Session aborted'
        'timeout'   = 'Session timed out'
        'user_exit' = 'Session ended'
    }

    $activity = Get-RepoActivity -Cwd $Cwd
    $task = Limit-ContextText -Text $activity.taskSummary -MaxLength 90

    $parts = [System.Collections.Generic.List[string]]::new()
    switch ($Reason) {
        'complete' {
            if ($task) { $parts.Add("Task complete: $task") } else { $parts.Add($fallbackMap['complete']) }
        }
        'error' {
            if ($task) { $parts.Add("Task failed: $task") } else { $parts.Add($fallbackMap['error']) }
        }
        'abort' {
            if ($task) { $parts.Add("Stopped: $task") } else { $parts.Add($fallbackMap['abort']) }
        }
        'timeout' {
            if ($task) { $parts.Add("Timed out on: $task") } else { $parts.Add($fallbackMap['timeout']) }
        }
        'user_exit' {
            if ($task) { $parts.Add("Stopped: $task") } else { $parts.Add($fallbackMap['user_exit']) }
        }
        default {
            if ($task) { $parts.Add("Session ended: $task") } else { $parts.Add('Session ended') }
        }
    }

    $detailParts = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($activity.whySummary) -and
        $activity.whySummary.ToLowerInvariant() -ne $task.ToLowerInvariant()) {
        Add-RecapPart -Parts $detailParts -Text $activity.whySummary
    }
    foreach ($milestone in @($activity.milestones | Select-Object -Last 2)) {
        Add-RecapPart -Parts $detailParts -Text ([string]$milestone)
    }
    Add-RecapPart -Parts $detailParts -Text $activity.latestOutcome

    if ($detailParts.Count -eq 0 -and [string]::IsNullOrWhiteSpace($task)) {
        $fallback = if ($fallbackMap.ContainsKey($Reason)) { $fallbackMap[$Reason] } else { 'Session ended' }
        return Sanitize-TextForTTS -Text $fallback
    }

    foreach ($detail in $detailParts) {
        $candidate = @($parts + $detail) -join '. '
        if ((Sanitize-TextForTTS -Text $candidate).Length -gt 200) { break }
        $parts.Add($detail)
    }

    return Sanitize-TextForTTS -Text ($parts -join '. ')
}

#endregion
