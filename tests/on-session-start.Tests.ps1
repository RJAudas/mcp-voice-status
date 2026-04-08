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
        $activity = Get-RepoActivityFromStateFile -Path $script:StateFile
        $activity.taskSummary | Should -Be 'Fix the auth bug'
    }

    It 'resets any previous session activity when a new session starts' {
        @{
            lastSpokenAt   = 0
            recentMessages = @()
            repoActivities = @(@{
                cwd           = 'C:\repo'
                taskSummary   = 'Old work'
                whySummary    = ''
                milestones    = @('Edited old-file.ps1')
                latestOutcome = 'Build failed'
                lastReason    = ''
                lastUpdatedAt = 0
            })
        } | ConvertTo-Json -Depth 10 | Set-Content $script:StateFile

        $json = New-MockPayload 'sessionStart' @{ initialPrompt = '' }
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-session-start.ps1") -InputJson $json
        $LASTEXITCODE | Should -Be 0
        $activity = Get-RepoActivityFromStateFile -Path $script:StateFile
        $activity.taskSummary | Should -Be ''
        @($activity.milestones).Count | Should -Be 0
        $activity.latestOutcome | Should -Be ''
    }

    It 'exits 0 with source=resume' {
        $json = New-MockPayload 'sessionStart' @{ source = 'resume'; initialPrompt = 'Resuming work on tests' }
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-session-start.ps1") -InputJson $json
        $LASTEXITCODE | Should -Be 0
        $activity = Get-RepoActivityFromStateFile -Path $script:StateFile
        $activity.taskSummary | Should -Be 'Resuming work on tests'
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
