#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . "$PSScriptRoot\test-helpers.ps1"
    . (Join-Path $PSScriptRoot "..\.github\hooks\scripts\voice-status-common.ps1")
    $env:VOICE_STATUS_SKIP_TTS = '1'
}

AfterAll {
    $env:VOICE_STATUS_SKIP_TTS = $null
}

Describe 'on-session-end.ps1' {
    BeforeEach {
        $script:StateFile = Join-Path $env:TEMP "voice-status-state.json"
        Remove-Item $script:StateFile -Force -ErrorAction SilentlyContinue
    }

    It 'exits 0 for reason=complete' {
        $json = New-MockPayload 'sessionEnd' @{ reason = 'complete' }
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-session-end.ps1") -InputJson $json
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 for reason=error' {
        $json = New-MockPayload 'sessionEnd' @{ reason = 'error' }
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-session-end.ps1") -InputJson $json
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 for reason=abort' {
        $json = New-MockPayload 'sessionEnd' @{ reason = 'abort' }
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-session-end.ps1") -InputJson $json
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 for reason=timeout' {
        $json = New-MockPayload 'sessionEnd' @{ reason = 'timeout' }
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-session-end.ps1") -InputJson $json
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 for reason=user_exit' {
        $json = New-MockPayload 'sessionEnd' @{ reason = 'user_exit' }
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-session-end.ps1") -InputJson $json
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 with malformed JSON (no crash)' {
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-session-end.ps1") -InputJson 'bad json'
        $LASTEXITCODE | Should -Be 0
    }
}
