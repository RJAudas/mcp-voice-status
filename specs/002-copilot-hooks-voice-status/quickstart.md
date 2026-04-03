# Quickstart: Copilot Agent Hooks Voice Status

**Branch**: `002-copilot-hooks-voice-status` | **Date**: 2026-04-03

## Prerequisites

- Windows 10 or 11
- PowerShell 5.1 (built-in)
- Audio output configured
- GitHub Copilot (cloud agent or CLI)

## Installation

Copy the hooks directory into your repository:

```
your-repo/
└── .github/
    └── hooks/
        ├── voice-status.json              # Hook configuration
        └── scripts/
            ├── voice-status-config.json   # Settings (optional, has defaults)
            ├── voice-status-common.ps1    # Shared module
            ├── on-session-start.ps1       # Session start handler
            ├── on-session-end.ps1         # Session end handler
            ├── on-prompt-submitted.ps1    # User prompt handler
            ├── on-post-tool-use.ps1       # Tool completion handler
            └── on-error.ps1              # Error handler
```

Commit to the default branch (required for cloud agent).

## Verify It Works

### Quick TTS test

```powershell
Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$synth.Speak("Voice status ready")
$synth.Dispose()
```

### Test a hook script

```powershell
# Simulate a session start event
'{"timestamp":1704614400000,"cwd":".","source":"new","initialPrompt":"Fix the auth bug"}' | 
  powershell -File .github/hooks/scripts/on-session-start.ps1
```

### Test tool filtering

```powershell
# This should speak (edit is "interesting")
'{"timestamp":1704614400000,"cwd":".","toolName":"edit","toolArgs":"{\"path\":\"src/auth.ts\"}","toolResult":{"resultType":"success","textResultForLlm":"File edited"}}' | 
  powershell -File .github/hooks/scripts/on-post-tool-use.ps1

# This should be silent (view is "noisy")
'{"timestamp":1704614400000,"cwd":".","toolName":"view","toolArgs":"{}","toolResult":{"resultType":"success","textResultForLlm":"File contents"}}' | 
  powershell -File .github/hooks/scripts/on-post-tool-use.ps1
```

## Configuration

### Edit JSON config

Edit `.github/hooks/scripts/voice-status-config.json`:

```json
{
  "interestingTools": ["edit", "create", "bash", "powershell", "write_powershell", "task"],
  "rateLimitMs": 3000,
  "dedupWindowMs": 10000,
  "voiceRate": 0,
  "voiceVolume": 100
}
```

### Or use environment variables

```powershell
$env:VOICE_STATUS_RATE_LIMIT_MS = "5000"     # 5 second rate limit
$env:VOICE_STATUS_VOLUME = "50"               # 50% volume
$env:VOICE_STATUS_RATE = "2"                  # Slightly faster speech
```

## What You'll Hear

| Event | Example Message |
|-------|----------------|
| Session start | "Session started. Fix the auth bug" |
| User prompt | "New task: add unit tests for login" |
| Edit file | "Edited auth-controller.ts" |
| Build command | "Build succeeded" or "3 tests failed" |
| Error | "Error: network timeout" |
| Session end | "Session complete" |

## Running Tests

```powershell
# Install Pester if needed
Install-Module -Name Pester -Force -SkipPublisherCheck

# Run all tests
Invoke-Pester -Path tests/
```
