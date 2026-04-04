#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . "$PSScriptRoot\test-helpers.ps1"
    . (Join-Path $PSScriptRoot "..\.github\hooks\scripts\voice-status-common.ps1")
    $env:VOICE_STATUS_SKIP_TTS = '1'
}

AfterAll {
    $env:VOICE_STATUS_SKIP_TTS = $null
}

Describe 'on-session-start.ps1' {
    BeforeEach {
        # Clean state file before each test
        $script:StateFile = Join-Path $env:TEMP "voice-status-state.json"
        Remove-Item $script:StateFile -Force -ErrorAction SilentlyContinue
        Reset-MockSpeechLog
    }

    It 'speaks session started with initial prompt (source=new)' {
        $json = New-MockPayload 'sessionStart' @{ source = 'new'; initialPrompt = 'Fix the auth bug' }
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-session-start.ps1") -InputJson $json
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 with missing/empty initialPrompt' {
        $json = New-MockPayload 'sessionStart' @{ initialPrompt = '' }
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-session-start.ps1") -InputJson $json
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 with source=resume' {
        $json = New-MockPayload 'sessionStart' @{ source = 'resume'; initialPrompt = 'Resuming work on tests' }
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-session-start.ps1") -InputJson $json
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 with malformed JSON (no crash)' {
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-session-start.ps1") -InputJson 'this is not json'
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 with empty stdin' {
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-session-start.ps1") -InputJson ''
        $LASTEXITCODE | Should -Be 0
    }
}
