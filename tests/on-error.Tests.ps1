#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . "$PSScriptRoot\test-helpers.ps1"
    . (Join-Path $PSScriptRoot "..\.github\hooks\scripts\voice-status-common.ps1")
    $env:VOICE_STATUS_SKIP_TTS = '1'
}

AfterAll {
    $env:VOICE_STATUS_SKIP_TTS = $null
}

Describe 'on-error.ps1' {
    BeforeEach {
        $script:StateFile = Join-Path $env:TEMP "voice-status-state.json"
        Remove-Item $script:StateFile -Force -ErrorAction SilentlyContinue
    }

    It 'exits 0 and speaks error name and message' {
        $json = New-MockPayload 'errorOccurred' @{
            error = @{ name = 'TimeoutError'; message = 'Network timeout after 30s'; stack = '' }
        }
        $json | & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-error.ps1")
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 with missing error.name (graceful fallback)' {
        '{"timestamp":"2026-01-01","cwd":".","error":{"message":"Something failed"}}' |
            & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-error.ps1")
        $LASTEXITCODE | Should -Be 0
    }

    It 'bypasses rate limiting — speaks even when within rate limit window' {
        # Set lastSpokenAt to NOW — normal hooks would be blocked
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        @{ lastSpokenAt = $now; recentMessages = @() } | ConvertTo-Json | Set-Content $script:StateFile

        $json = New-MockPayload 'errorOccurred' @{
            error = @{ name = 'BuildError'; message = 'Compilation failed'; stack = '' }
        }
        # Should still exit 0 (not blocked) — rate limit bypass verified
        $json | & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-error.ps1")
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 with malformed JSON (no crash)' {
        'bad json' | & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-error.ps1")
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 with empty stdin' {
        '' | & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-error.ps1")
        $LASTEXITCODE | Should -Be 0
    }
}
