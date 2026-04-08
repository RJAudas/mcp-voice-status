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
        Update-RepoActivity -Cwd 'C:\repo' -TaskSummary 'Fix auth bug' -Milestone 'Edited auth.ts' -Outcome '15 tests passed' -Reset | Out-Null
        $json = New-MockPayload 'sessionEnd' @{ reason = 'complete' }
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-session-end.ps1") -InputJson $json
        $LASTEXITCODE | Should -Be 0
        Get-RepoActivityFromStateFile -Path $script:StateFile | Should -BeNullOrEmpty
    }

    It 'exits 0 for reason=error' {
        Update-RepoActivity -Cwd 'C:\repo' -TaskSummary 'Fix auth bug' -Outcome 'Build failed' -Reset | Out-Null
        $json = New-MockPayload 'sessionEnd' @{ reason = 'error' }
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-session-end.ps1") -InputJson $json
        $LASTEXITCODE | Should -Be 0
        Get-RepoActivityFromStateFile -Path $script:StateFile | Should -BeNullOrEmpty
    }

    It 'exits 0 for reason=abort' {
        Update-RepoActivity -Cwd 'C:\repo' -TaskSummary 'Fix auth bug' -Reset | Out-Null
        $json = New-MockPayload 'sessionEnd' @{ reason = 'abort' }
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-session-end.ps1") -InputJson $json
        $LASTEXITCODE | Should -Be 0
        Get-RepoActivityFromStateFile -Path $script:StateFile | Should -BeNullOrEmpty
    }

    It 'exits 0 for reason=timeout' {
        Update-RepoActivity -Cwd 'C:\repo' -TaskSummary 'Fix auth bug' -Reset | Out-Null
        $json = New-MockPayload 'sessionEnd' @{ reason = 'timeout' }
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-session-end.ps1") -InputJson $json
        $LASTEXITCODE | Should -Be 0
        Get-RepoActivityFromStateFile -Path $script:StateFile | Should -BeNullOrEmpty
    }

    It 'exits 0 for reason=user_exit' {
        Update-RepoActivity -Cwd 'C:\repo' -TaskSummary 'Fix auth bug' -Reset | Out-Null
        $json = New-MockPayload 'sessionEnd' @{ reason = 'user_exit' }
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-session-end.ps1") -InputJson $json
        $LASTEXITCODE | Should -Be 0
        Get-RepoActivityFromStateFile -Path $script:StateFile | Should -BeNullOrEmpty
    }

    It 'exits 0 with malformed JSON (no crash)' {
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-session-end.ps1") -InputJson 'bad json'
        $LASTEXITCODE | Should -Be 0
    }
}
