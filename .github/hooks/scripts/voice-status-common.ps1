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

    $resultText = ''
    if ($null -ne $ToolResult -and -not [string]::IsNullOrWhiteSpace($ToolResult.textResultForLlm)) {
        $resultText = $ToolResult.textResultForLlm
    }

    switch ($ToolName) {
        'edit' {
            $filename = Get-FilenameFromArgs $ToolArgs
            if ($filename) { return "Edited $filename" }
            return 'File edited'
        }
        'create' {
            $filename = Get-FilenameFromArgs $ToolArgs
            if ($filename) { return "Created $filename" }
            return 'File created'
        }
        { $_ -in @('bash', 'powershell', 'write_powershell') } {
            return Get-CommandSummary $resultText
        }
        'task' {
            return 'Task completed'
        }
        default {
            return $null  # Unknown/uninteresting — silent skip
        }
    }
}

function Get-FilenameFromArgs {
    param([string]$ToolArgs)
    if ([string]::IsNullOrWhiteSpace($ToolArgs)) { return $null }
    try {
        $parsedArgs = $ToolArgs | ConvertFrom-Json -ErrorAction Stop
        # Try common field names for file path
        $path = $null
        foreach ($propertyName in @('path', 'file_path', 'filename', 'target_file')) {
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
    param([string]$Output)

    if ([string]::IsNullOrWhiteSpace($Output)) { return 'Command completed' }

    $o = $Output.ToLower()

    # Test results: "N tests passed" / "N tests failed"
    if ($o -match '(\d+)\s+(?:tests?|specs?|examples?)\s+passed' -or
        $o -match 'all\s+(\d+)\s+(?:tests?|specs?)\s+passed' -or
        $o -match '(\d+)\s+passing') {
        $passed = $Matches[1]
        if ($o -match '(\d+)\s+(?:tests?|specs?|examples?)\s+failed' -or
            $o -match '(\d+)\s+failing') {
            $failed = $Matches[1]
            return "$passed passed, $failed failed"
        }
        return "$passed tests passed"
    }
    if ($o -match '(\d+)\s+(?:tests?|specs?|examples?)\s+failed' -or
        $o -match '(\d+)\s+failing') {
        return "$($Matches[1]) tests failed"
    }

    # Build results
    if ($o -match 'build\s+succeeded' -or $o -match 'build\s+success') { return 'Build succeeded' }
    if ($o -match 'build\s+failed' -or $o -match 'build\s+error') { return 'Build failed' }

    # Lint results: "N errors, M warnings" or "X problems (Y errors, Z warnings)"
    if ($o -match '(\d+)\s+errors?,\s*(\d+)\s+warnings?') {
        $errors   = $Matches[1]
        $warnings = $Matches[2]
        if ($errors -eq '0' -and $warnings -eq '0') { return 'Lint passed' }
        if ($errors -eq '0') { return "Lint: $warnings warnings" }
        return "Lint: $errors errors, $warnings warnings"
    }
    if ($o -match '(\d+)\s+problems?' -and $o -match '(\d+)\s+errors?') {
        return "Lint: $($Matches[1]) problems"
    }

    return 'Command completed'
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

function Get-SpeechState {
    try {
        if (Test-Path $script:StateFile) {
            $raw = Get-Content $script:StateFile -Raw -ErrorAction Stop
            return $raw | ConvertFrom-Json -ErrorAction Stop
        }
    } catch { }
    return [PSCustomObject]@{ lastSpokenAt = 0; recentMessages = @() }
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

    # Atomic write: write to temp then move
    $tmp = $script:StateFile + ".tmp"
    try {
        $state | ConvertTo-Json -Compress | Set-Content -Path $tmp -Encoding UTF8 -ErrorAction Stop
        Move-Item -Path $tmp -Destination $script:StateFile -Force -ErrorAction Stop
    } catch {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
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

#endregion
