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
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-prompt-submitted.ps1") -InputJson $json
        $LASTEXITCODE | Should -Be 0
        $activity = Get-RepoActivityFromStateFile -Path $script:StateFile
        $activity.taskSummary | Should -Be 'Add unit tests for the login module'
    }

    It 'resets prior milestones when a new prompt arrives' {
        @{
            lastSpokenAt   = 0
            recentMessages = @()
            repoActivities = @(@{
                cwd           = 'C:\repo'
                taskSummary   = 'Old task'
                whySummary    = ''
                milestones    = @('Edited auth.ts')
                latestOutcome = 'Build failed'
                lastReason    = ''
                lastUpdatedAt = 0
            })
        } | ConvertTo-Json -Depth 10 | Set-Content $script:StateFile

        $json = New-MockPayload 'userPromptSubmitted' @{ prompt = 'Add unit tests for the login module' }
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-prompt-submitted.ps1") -InputJson $json
        $LASTEXITCODE | Should -Be 0
        $activity = Get-RepoActivityFromStateFile -Path $script:StateFile
        $activity.taskSummary | Should -Be 'Add unit tests for the login module'
        @($activity.milestones).Count | Should -Be 0
        $activity.latestOutcome | Should -Be ''
    }

    It 'exits 0 silently for empty prompt' {
        $json = New-MockPayload 'userPromptSubmitted' @{ prompt = '' }
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-prompt-submitted.ps1") -InputJson $json
        $LASTEXITCODE | Should -Be 0
        Get-RepoActivityFromStateFile -Path $script:StateFile | Should -BeNullOrEmpty
    }

    It 'exits 0 silently for missing prompt field' {
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-prompt-submitted.ps1") -InputJson '{"timestamp":"2026-01-01","cwd":"."}'
        $LASTEXITCODE | Should -Be 0
        Get-RepoActivityFromStateFile -Path $script:StateFile | Should -BeNullOrEmpty
    }

    It 'exits 0 for very long prompt (truncated to 200 chars total)' {
        $longPrompt = 'A' * 500
        $json = New-MockPayload 'userPromptSubmitted' @{ prompt = $longPrompt }
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-prompt-submitted.ps1") -InputJson $json
        $LASTEXITCODE | Should -Be 0
        $activity = Get-RepoActivityFromStateFile -Path $script:StateFile
        $activity.taskSummary.Length | Should -BeLessOrEqual 110
    }

    It 'exits 0 with malformed JSON (no crash)' {
        & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-prompt-submitted.ps1") -InputJson 'not json at all'
        $LASTEXITCODE | Should -Be 0
    }
}
