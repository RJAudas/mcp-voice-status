#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . "$PSScriptRoot\test-helpers.ps1"
    . (Join-Path $PSScriptRoot "..\.github\hooks\scripts\voice-status-common.ps1")
    $env:VOICE_STATUS_SKIP_TTS = '1'
}

AfterAll {
    $env:VOICE_STATUS_SKIP_TTS = $null
}

Describe 'on-prompt-submitted.ps1' {
    BeforeEach {
        $script:StateFile = Join-Path $env:TEMP "voice-status-state.json"
        Remove-Item $script:StateFile -Force -ErrorAction SilentlyContinue
    }

    It 'exits 0 for normal prompt' {
        $json = New-MockPayload 'userPromptSubmitted' @{ prompt = 'Add unit tests for the login module' }
        $json | & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-prompt-submitted.ps1")
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 silently for empty prompt' {
        $json = New-MockPayload 'userPromptSubmitted' @{ prompt = '' }
        $json | & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-prompt-submitted.ps1")
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 silently for missing prompt field' {
        '{"timestamp":"2026-01-01","cwd":"."}' |
            & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-prompt-submitted.ps1")
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 for very long prompt (truncated to 200 chars total)' {
        $longPrompt = 'A' * 500
        $json = New-MockPayload 'userPromptSubmitted' @{ prompt = $longPrompt }
        $json | & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-prompt-submitted.ps1")
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 with malformed JSON (no crash)' {
        'not json at all' | & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-prompt-submitted.ps1")
        $LASTEXITCODE | Should -Be 0
    }
}
