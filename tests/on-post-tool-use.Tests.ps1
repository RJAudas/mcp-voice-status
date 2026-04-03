#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . "$PSScriptRoot\test-helpers.ps1"
    . (Join-Path $PSScriptRoot "..\.github\hooks\scripts\voice-status-common.ps1")
    $env:VOICE_STATUS_SKIP_TTS = '1'
}

AfterAll {
    $env:VOICE_STATUS_SKIP_TTS = $null
}

Describe 'on-post-tool-use.ps1' {
    BeforeEach {
        $script:StateFile = Join-Path $env:TEMP "voice-status-state.json"
        Remove-Item $script:StateFile -Force -ErrorAction SilentlyContinue
    }

    It 'exits 0 for interesting tool (edit) — no crash' {
        $json = New-MockPayload 'postToolUse' @{
            toolName   = 'edit'
            toolArgs   = '{"path":"src/auth.ts"}'
            toolResult = @{ resultType = 'success'; textResultForLlm = 'Updated.' }
        }
        $json | & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-post-tool-use.ps1")
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 silently for noisy tool (view)' {
        $json = New-MockPayload 'postToolUse' @{ toolName = 'view'; toolArgs = '{}' }
        $json | & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-post-tool-use.ps1")
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 silently for noisy tool (grep)' {
        $json = New-MockPayload 'postToolUse' @{ toolName = 'grep'; toolArgs = '{}' }
        $json | & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-post-tool-use.ps1")
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 silently for noisy tool (glob)' {
        $json = New-MockPayload 'postToolUse' @{ toolName = 'glob'; toolArgs = '{}' }
        $json | & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-post-tool-use.ps1")
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 silently for unrecognized tool name (FR-008)' {
        $json = New-MockPayload 'postToolUse' @{ toolName = 'unknown_future_tool'; toolArgs = '{}' }
        $json | & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-post-tool-use.ps1")
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 for bash tool with test output' {
        $json = New-MockPayload 'postToolUse' @{
            toolName   = 'bash'
            toolArgs   = '{"command":"npm test"}'
            toolResult = @{ resultType = 'success'; textResultForLlm = '15 tests passed, 0 failed' }
        }
        $json | & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-post-tool-use.ps1")
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 with malformed JSON (no crash)' {
        'bad json {{{' | & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-post-tool-use.ps1")
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 with empty stdin' {
        '' | & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-post-tool-use.ps1")
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 0 for tool failure (bypasses rate limit)' {
        # Set lastSpokenAt to now so rate limit would normally block
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        @{ lastSpokenAt = $now; recentMessages = @() } | ConvertTo-Json | Set-Content $script:StateFile
        $json = New-MockPayload 'postToolUse' @{
            toolName   = 'bash'
            toolArgs   = '{}'
            toolResult = @{ resultType = 'failure'; textResultForLlm = 'Build failed' }
        }
        $json | & (Join-Path $PSScriptRoot "..\.github\hooks\scripts\on-post-tool-use.ps1")
        $LASTEXITCODE | Should -Be 0
    }
}
