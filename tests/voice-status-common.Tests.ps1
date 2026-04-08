#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$CommonModule = Join-Path $PSScriptRoot "..\.github\hooks\scripts\voice-status-common.ps1"

BeforeAll {
    . (Join-Path $PSScriptRoot "..\.github\hooks\scripts\voice-status-common.ps1")
}

Describe 'Get-VoiceStatusConfig' {
    BeforeEach {
        # Clear env vars before each test
        $envVars = @('VOICE_STATUS_RATE_LIMIT_MS','VOICE_STATUS_DEDUP_WINDOW_MS',
                     'VOICE_STATUS_TIMEOUT_MS','VOICE_STATUS_VOLUME','VOICE_STATUS_RATE')
        $envVars | ForEach-Object { [System.Environment]::SetEnvironmentVariable($_, $null) }
    }

    It 'returns default values when config file is missing' {
        $cfg = Get-VoiceStatusConfig -ConfigPath "C:\nonexistent\path\voice-status-config.json"
        $cfg.rateLimitMs   | Should -Be 3000
        $cfg.dedupWindowMs | Should -Be 10000
        $cfg.ttsTimeoutMs  | Should -Be 30000
        $cfg.voiceVolume   | Should -Be 100
        $cfg.voiceRate     | Should -Be 0
    }

    It 'loads values from valid JSON config' {
        $cfgPath = Join-Path $env:TEMP "vs-cfg-$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).json"
        @{ rateLimitMs = 5000; dedupWindowMs = 15000; ttsTimeoutMs = 20000; voiceRate = 2; voiceVolume = 80 } |
            ConvertTo-Json | Set-Content $cfgPath
        try {
            $cfg = Get-VoiceStatusConfig -ConfigPath $cfgPath
            $cfg.rateLimitMs   | Should -Be 5000
            $cfg.dedupWindowMs | Should -Be 15000
            $cfg.voiceVolume   | Should -Be 80
        } finally {
            Remove-Item $cfgPath -Force -ErrorAction SilentlyContinue
        }
    }

    It 'falls back to defaults on malformed JSON' {
        $cfgPath = Join-Path $env:TEMP "vs-cfg-$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).json"
        'this is { not valid json ][' | Set-Content $cfgPath
        try {
            $cfg = Get-VoiceStatusConfig -ConfigPath $cfgPath
            $cfg.rateLimitMs | Should -Be 3000
        } finally {
            Remove-Item $cfgPath -Force -ErrorAction SilentlyContinue
        }
    }

    It 'overrides with env vars' {
        [System.Environment]::SetEnvironmentVariable('VOICE_STATUS_RATE_LIMIT_MS', '7000')
        [System.Environment]::SetEnvironmentVariable('VOICE_STATUS_VOLUME', '50')
        $cfg = Get-VoiceStatusConfig -ConfigPath "C:\nonexistent\path\voice-status-config.json"
        $cfg.rateLimitMs  | Should -Be 7000
        $cfg.voiceVolume  | Should -Be 50
    }

    It 'ignores non-numeric env var and keeps JSON/default value' {
        [System.Environment]::SetEnvironmentVariable('VOICE_STATUS_VOLUME', 'loud')
        $cfg = Get-VoiceStatusConfig -ConfigPath "C:\nonexistent\path\voice-status-config.json"
        $cfg.voiceVolume | Should -Be 100
    }

    It 'clamps rateLimitMs below minimum to 1000' {
        [System.Environment]::SetEnvironmentVariable('VOICE_STATUS_RATE_LIMIT_MS', '100')
        $cfg = Get-VoiceStatusConfig -ConfigPath "C:\nonexistent\path\voice-status-config.json"
        $cfg.rateLimitMs | Should -Be 1000
    }

    It 'clamps voiceVolume above 100 to 100' {
        [System.Environment]::SetEnvironmentVariable('VOICE_STATUS_VOLUME', '200')
        $cfg = Get-VoiceStatusConfig -ConfigPath "C:\nonexistent\path\voice-status-config.json"
        $cfg.voiceVolume | Should -Be 100
    }

    It 'handles partial config: missing fields get defaults' {
        $cfgPath = Join-Path $env:TEMP "vs-cfg-$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).json"
        '{"rateLimitMs":4000}' | Set-Content $cfgPath
        try {
            $cfg = Get-VoiceStatusConfig -ConfigPath $cfgPath
            $cfg.rateLimitMs   | Should -Be 4000
            $cfg.dedupWindowMs | Should -Be 10000  # default kept
            $cfg.voiceVolume   | Should -Be 100    # default kept
        } finally {
            Remove-Item $cfgPath -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Sanitize-TextForTTS' {
    It 'returns empty string for null input' {
        Sanitize-TextForTTS -Text $null | Should -Be ''
    }

    It 'returns empty string for empty input' {
        Sanitize-TextForTTS -Text '' | Should -Be ''
    }

    It 'passes through normal text unchanged' {
        Sanitize-TextForTTS -Text 'Build succeeded' | Should -Be 'Build succeeded'
    }

    It 'escapes single quotes by doubling' {
        Sanitize-TextForTTS -Text "It's done" | Should -Be "It''s done"
    }

    It 'removes backticks' {
        Sanitize-TextForTTS -Text 'Run `npm test`' | Should -Be 'Run npm test'
    }

    It 'strips SSML XML tags' {
        Sanitize-TextForTTS -Text '<speak>Hello</speak>' | Should -Be 'Hello'
    }

    It 'removes null bytes' {
        Sanitize-TextForTTS -Text "Hello`0World" | Should -Be 'Hello World'
    }

    It 'truncates to 200 chars' {
        $long = 'A' * 250
        $result = Sanitize-TextForTTS -Text $long
        $result.Length | Should -Be 200
    }

    It 'respects custom MaxLength' {
        $result = Sanitize-TextForTTS -Text 'Hello World' -MaxLength 5
        $result.Length | Should -BeLessOrEqual 5
    }

    It 'collapses multiple whitespace' {
        Sanitize-TextForTTS -Text "Hello   World`t`n!" | Should -Be 'Hello World !'
    }

    It 'removes control characters' {
        # ESC character (\x1B)
        $text = "Hello" + [char]0x1B + "World"
        Sanitize-TextForTTS -Text $text | Should -Be 'Hello World'
    }

    It 'removes double quotes' {
        Sanitize-TextForTTS -Text 'He said "hello"' | Should -Be 'He said hello'
    }

    It 'blocks PowerShell injection attempt' {
        # Injection vector for TTS: single quotes can escape the string literal.
        # The sanitizer doubles single quotes so the text stays inside the quoted string.
        $injection = "foo'; Remove-Item C:\Windows -Recurse; '"
        $result = Sanitize-TextForTTS -Text $injection
        # Result must not contain an unescaped single quote (would break TTS string embedding)
        $result | Should -Not -Match "(?<!')'(?!')"
        # Doubling of the original single quotes confirms escaping occurred
        $result | Should -Match "''"
    }

    It 'blocks backtick injection attempt' {
        $injection = '`$(malicious code)`'
        $result = Sanitize-TextForTTS -Text $injection
        $result | Should -Not -Contain '`'
    }
}

Describe 'Get-ToolSummary' {
    It 'returns Edited filename for edit tool' {
        $result = Get-ToolSummary -ToolName 'edit' -ToolArgs '{"path":"src/auth.ts"}' -ToolResult $null
        $result | Should -Be 'Edited auth.ts'
    }

    It 'returns Created filename for create tool' {
        $result = Get-ToolSummary -ToolName 'create' -ToolArgs '{"path":"src/new-file.ts"}' -ToolResult $null
        $result | Should -Be 'Created new-file.ts'
    }

    It 'returns fallback for edit tool without path' {
        $result = Get-ToolSummary -ToolName 'edit' -ToolArgs '{}' -ToolResult $null
        $result | Should -Be 'File edited'
    }

    It 'summarizes bash test output with passing tests' {
        $toolResult = [PSCustomObject]@{ resultType = 'success'; textResultForLlm = '15 tests passed, 0 failed' }
        $result = Get-ToolSummary -ToolName 'bash' -ToolArgs '{}' -ToolResult $toolResult
        $result | Should -Match '15'
        $result | Should -Match 'passed'
    }

    It 'summarizes bash test output with failing tests' {
        $toolResult = [PSCustomObject]@{ resultType = 'success'; textResultForLlm = '13 tests passed, 2 tests failed' }
        $result = Get-ToolSummary -ToolName 'bash' -ToolArgs '{}' -ToolResult $toolResult
        $result | Should -Match '2'
        $result | Should -Match 'failed'
    }

    It 'summarizes bash lint output with warnings' {
        $toolResult = [PSCustomObject]@{ resultType = 'success'; textResultForLlm = '0 errors, 2 warnings' }
        $result = Get-ToolSummary -ToolName 'bash' -ToolArgs '{}' -ToolResult $toolResult
        $result | Should -Be 'Lint: 2 warnings'
    }

    It 'summarizes bash lint output with errors and warnings' {
        $toolResult = [PSCustomObject]@{ resultType = 'success'; textResultForLlm = '3 errors, 1 warnings' }
        $result = Get-ToolSummary -ToolName 'bash' -ToolArgs '{}' -ToolResult $toolResult
        $result | Should -Match 'errors'
    }

    It 'summarizes bash build succeeded' {
        $toolResult = [PSCustomObject]@{ resultType = 'success'; textResultForLlm = 'Build succeeded in 3.2s' }
        $result = Get-ToolSummary -ToolName 'bash' -ToolArgs '{}' -ToolResult $toolResult
        $result | Should -Be 'Build succeeded'
    }

    It 'summarizes bash build failed' {
        $toolResult = [PSCustomObject]@{ resultType = 'failure'; textResultForLlm = 'Build failed: 3 errors' }
        $result = Get-ToolSummary -ToolName 'bash' -ToolArgs '{}' -ToolResult $toolResult
        $result | Should -Be 'Build failed'
    }

    It 'includes command intent when description is present' {
        $toolResult = [PSCustomObject]@{ resultType = 'success'; textResultForLlm = '15 tests passed, 0 failed' }
        $result = Get-ToolSummary -ToolName 'bash' -ToolArgs '{"description":"Run login tests"}' -ToolResult $toolResult
        $result | Should -Be 'Run login tests. 15 tests passed'
    }

    It 'returns null for generic bash output without context' {
        $toolResult = [PSCustomObject]@{ resultType = 'success'; textResultForLlm = 'some arbitrary output' }
        $result = Get-ToolSummary -ToolName 'bash' -ToolArgs '{}' -ToolResult $toolResult
        $result | Should -BeNullOrEmpty
    }

    It 'returns null for unknown tool names' {
        $result = Get-ToolSummary -ToolName 'unknown_tool_xyz' -ToolArgs '{}' -ToolResult $null
        $result | Should -BeNullOrEmpty
    }

    It 'handles null ToolArgs gracefully' {
        $result = Get-ToolSummary -ToolName 'edit' -ToolArgs $null -ToolResult $null
        $result | Should -Be 'File edited'
    }
}

Describe 'Repo activity state' {
    BeforeEach {
        $script:StateFile = Join-Path $env:TEMP "voice-status-state-test-$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).json"
        Remove-Item $script:StateFile -Force -ErrorAction SilentlyContinue
    }
    AfterEach {
        if (Test-Path $script:StateFile) { Remove-Item $script:StateFile -Force -ErrorAction SilentlyContinue }
    }

    It 'stores repo activity by cwd' {
        Update-RepoActivity -Cwd 'C:\repo-a' -TaskSummary 'Fix auth bug' -Milestone 'Edited auth.ts' -Outcome '15 tests passed' -Reset | Out-Null
        $activity = Get-RepoActivity -Cwd 'C:\repo-a'
        $activity.taskSummary | Should -Be 'Fix auth bug'
        @($activity.milestones) | Should -Contain 'Edited auth.ts'
        $activity.latestOutcome | Should -Be '15 tests passed'
    }

    It 'resets milestones and outcomes when Reset is used' {
        Update-RepoActivity -Cwd 'C:\repo-a' -TaskSummary 'Old task' -Milestone 'Edited old.ts' -Outcome 'Build failed' -Reset | Out-Null
        Update-RepoActivity -Cwd 'C:\repo-a' -TaskSummary 'New task' -Reset | Out-Null
        $activity = Get-RepoActivity -Cwd 'C:\repo-a'
        $activity.taskSummary | Should -Be 'New task'
        @($activity.milestones).Count | Should -Be 0
        $activity.latestOutcome | Should -Be ''
    }

    It 'builds a contextual recap from task milestones and outcome' {
        Update-RepoActivity -Cwd 'C:\repo-a' -TaskSummary 'Fix auth bug' -Milestone 'Edited auth.ts' -Outcome '15 tests passed' -Reset | Out-Null
        $recap = Build-SessionRecap -Cwd 'C:\repo-a' -Reason 'complete'
        $recap | Should -Match 'Task complete: Fix auth bug'
        $recap | Should -Match 'Edited auth.ts'
        $recap | Should -Match '15 tests passed'
    }

    It 'falls back to a generic reason when no activity exists' {
        $recap = Build-SessionRecap -Cwd 'C:\repo-a' -Reason 'abort'
        $recap | Should -Be 'Session aborted'
    }

    It 'clears only the matching repo activity' {
        Update-RepoActivity -Cwd 'C:\repo-a' -TaskSummary 'Task A' -Reset | Out-Null
        Update-RepoActivity -Cwd 'C:\repo-b' -TaskSummary 'Task B' -Reset | Out-Null
        Clear-RepoActivity -Cwd 'C:\repo-a'
        (Get-RepoActivity -Cwd 'C:\repo-a').taskSummary | Should -Be ''
        (Get-RepoActivity -Cwd 'C:\repo-b').taskSummary | Should -Be 'Task B'
    }
}

Describe 'Test-IsInterestingTool' {
    BeforeAll {
        $script:TestConfig = @{
            interestingTools = @('edit','create','bash','powershell','write_powershell','task')
            noisyTools       = @('view','grep','glob','read_powershell','list_powershell','web_fetch')
        }
    }

    It 'returns true for edit' {
        Test-IsInterestingTool -ToolName 'edit' -Config $script:TestConfig | Should -BeTrue
    }

    It 'returns true for create' {
        Test-IsInterestingTool -ToolName 'create' -Config $script:TestConfig | Should -BeTrue
    }

    It 'returns true for bash' {
        Test-IsInterestingTool -ToolName 'bash' -Config $script:TestConfig | Should -BeTrue
    }

    It 'returns true for write_powershell' {
        Test-IsInterestingTool -ToolName 'write_powershell' -Config $script:TestConfig | Should -BeTrue
    }

    It 'returns false for view' {
        Test-IsInterestingTool -ToolName 'view' -Config $script:TestConfig | Should -BeFalse
    }

    It 'returns false for grep' {
        Test-IsInterestingTool -ToolName 'grep' -Config $script:TestConfig | Should -BeFalse
    }

    It 'returns false for glob' {
        Test-IsInterestingTool -ToolName 'glob' -Config $script:TestConfig | Should -BeFalse
    }

    It 'returns false for read_powershell' {
        Test-IsInterestingTool -ToolName 'read_powershell' -Config $script:TestConfig | Should -BeFalse
    }

    It 'returns false for web_fetch' {
        Test-IsInterestingTool -ToolName 'web_fetch' -Config $script:TestConfig | Should -BeFalse
    }

    It 'returns false for unrecognized tool names (treats as noisy, FR-008)' {
        Test-IsInterestingTool -ToolName 'unknown_future_tool' -Config $script:TestConfig | Should -BeFalse
    }

    It 'respects custom config overriding tool lists' {
        $customConfig = @{ interestingTools = @('my_custom_tool'); noisyTools = @('edit') }
        Test-IsInterestingTool -ToolName 'my_custom_tool' -Config $customConfig | Should -BeTrue
        Test-IsInterestingTool -ToolName 'edit' -Config $customConfig | Should -BeFalse
    }
}

Describe 'Test-RateLimited' {
    BeforeEach {
        $script:StateFile = Join-Path $env:TEMP "voice-status-state-test-$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).json"
    }
    AfterEach {
        if (Test-Path $script:StateFile) { Remove-Item $script:StateFile -Force -ErrorAction SilentlyContinue }
    }

    It 'returns false when state file is missing' {
        $cfg = @{ rateLimitMs = 3000 }
        Test-RateLimited -Config $cfg | Should -BeFalse
    }

    It 'returns false when interval has passed' {
        $past = ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) - 5000
        @{ lastSpokenAt = $past; recentMessages = @() } | ConvertTo-Json | Set-Content $script:StateFile
        $cfg = @{ rateLimitMs = 3000 }
        Test-RateLimited -Config $cfg | Should -BeFalse
    }

    It 'returns true when within rate limit window' {
        $recent = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        @{ lastSpokenAt = $recent; recentMessages = @() } | ConvertTo-Json | Set-Content $script:StateFile
        $cfg = @{ rateLimitMs = 3000 }
        Test-RateLimited -Config $cfg | Should -BeTrue
    }

    It 'handles corrupted state file gracefully (returns false)' {
        'not valid json ][' | Set-Content $script:StateFile
        $cfg = @{ rateLimitMs = 3000 }
        Test-RateLimited -Config $cfg | Should -BeFalse
    }
}

Describe 'Test-IsDuplicate' {
    BeforeEach {
        $script:StateFile = Join-Path $env:TEMP "voice-status-state-test-$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).json"
    }
    AfterEach {
        if (Test-Path $script:StateFile) { Remove-Item $script:StateFile -Force -ErrorAction SilentlyContinue }
    }

    It 'returns false when state file is missing' {
        $cfg = @{ dedupWindowMs = 10000 }
        Test-IsDuplicate -Message 'Build succeeded' -Config $cfg | Should -BeFalse
    }

    It 'returns true for identical message within window' {
        $now  = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $hash = (Get-MessageHash 'build succeeded')
        @{ lastSpokenAt = $now; recentMessages = @(@{ hash = $hash; spokenAt = $now }) } |
            ConvertTo-Json | Set-Content $script:StateFile
        $cfg = @{ dedupWindowMs = 10000 }
        Test-IsDuplicate -Message 'Build succeeded' -Config $cfg | Should -BeTrue
    }

    It 'returns false for different message' {
        $now  = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $hash = (Get-MessageHash 'session complete')
        @{ lastSpokenAt = $now; recentMessages = @(@{ hash = $hash; spokenAt = $now }) } |
            ConvertTo-Json | Set-Content $script:StateFile
        $cfg = @{ dedupWindowMs = 10000 }
        Test-IsDuplicate -Message 'Build succeeded' -Config $cfg | Should -BeFalse
    }

    It 'returns false when dedup window has expired' {
        $expired = ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) - 20000
        $hash    = (Get-MessageHash 'build succeeded')
        @{ lastSpokenAt = $expired; recentMessages = @(@{ hash = $hash; spokenAt = $expired }) } |
            ConvertTo-Json | Set-Content $script:StateFile
        $cfg = @{ dedupWindowMs = 10000 }
        Test-IsDuplicate -Message 'Build succeeded' -Config $cfg | Should -BeFalse
    }

    It 'handles corrupted state file gracefully (returns false)' {
        'corrupted' | Set-Content $script:StateFile
        $cfg = @{ dedupWindowMs = 10000 }
        Test-IsDuplicate -Message 'any message' -Config $cfg | Should -BeFalse
    }
}
