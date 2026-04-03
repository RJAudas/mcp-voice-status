# Voice Status Hooks

Audible spoken status updates for GitHub Copilot agents on Windows — hands-free awareness of what your AI is doing.

Hook scripts fire **automatically** at agent lifecycle points (session start/end, tool use, prompts, errors) and speak brief summaries via Windows built-in text-to-speech. **Zero agent cooperation needed** — no system prompt changes, no explicit tool calls, no Node.js.

## Features

- 🗣️ **Session announcements** — Hear when a session starts, what task began, and when it ends
- 🔧 **Tool completion summaries** — "Edited auth.ts", "15 tests passed", "Build succeeded"
- 🔇 **Smart filtering** — Only speaks for meaningful actions; silently skips read-only tools (view, grep, glob)
- ⏱️ **Rate limiting** — Default 3-second minimum interval prevents audio spam
- 🔄 **Deduplication** — Identical messages within 10 seconds are silently dropped
- ⚡ **Error bypass** — Errors are always spoken immediately, skipping rate limiting
- ⚙️ **Configurable** — JSON config file + environment variable overrides
- 🔒 **Local only** — Zero network calls; all processing on-device via Windows System.Speech

## Prerequisites

- **Windows 10/11** (required for `System.Speech`)
- **PowerShell 5.1** (ships with Windows 10+)
- **GitHub Copilot** (cloud agent or CLI)
- **Audio output** configured and working

## Installation

1. **Copy** the `.github/hooks/` directory into your repository:

   ```powershell
   # From this repo, copy to your target repo
   Copy-Item -Recurse .github\hooks\ C:\path\to\your-repo\.github\hooks\
   ```

2. **Commit** the hooks to your default branch (required for Copilot cloud agent):

   ```powershell
   git add .github/hooks/
   git commit -m "Add voice status hooks"
   git push
   ```

3. **Verify** TTS works:

   ```powershell
   Add-Type -AssemblyName System.Speech
   $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
   $s.Speak("Voice status hooks installed successfully")
   ```

For detailed setup instructions, see [docs/setup.md](docs/setup.md).

## What You Will Hear

| Event | Example Spoken Output |
|-------|-----------------------|
| Session starts | "Session started. Fix the auth bug in login" |
| New prompt submitted | "New task: add unit tests for login" |
| File edited | "Edited auth-controller.ts" |
| File created | "Created test-helpers.ps1" |
| Tests run | "15 tests passed" or "3 tests failed" |
| Build completes | "Build succeeded" or "Build failed" |
| Error occurs | "Error: TimeoutError. Network timeout after 30s" |
| Session ends | "Session complete" or "Session aborted" |
| Noisy tool (view/grep/glob) | *(silence)* |

## Configuration

Voice behavior is configured via `.github/hooks/scripts/voice-status-config.json`:

```json
{
  "interestingTools": ["edit", "create", "bash", "powershell", "write_powershell", "task"],
  "noisyTools":       ["view", "grep", "glob", "read_powershell", "list_powershell", "web_fetch"],
  "rateLimitMs":      3000,
  "dedupWindowMs":    10000,
  "ttsTimeoutMs":     30000,
  "voiceRate":        0,
  "voiceVolume":      100
}
```

### Environment Variable Overrides

For quick per-session tuning without editing the JSON file:

| Variable | Config Key | Default | Description |
|----------|-----------|---------|-------------|
| `VOICE_STATUS_RATE_LIMIT_MS` | `rateLimitMs` | `3000` | Minimum ms between spoken messages |
| `VOICE_STATUS_DEDUP_WINDOW_MS` | `dedupWindowMs` | `10000` | Window for dedup (ms) |
| `VOICE_STATUS_TIMEOUT_MS` | `ttsTimeoutMs` | `30000` | TTS process max runtime (ms) |
| `VOICE_STATUS_VOLUME` | `voiceVolume` | `100` | TTS volume (0–100) |
| `VOICE_STATUS_RATE` | `voiceRate` | `0` | TTS speech rate (-10 to 10) |

Example:
```powershell
$env:VOICE_STATUS_VOLUME = "70"
$env:VOICE_STATUS_RATE_LIMIT_MS = "5000"
```

## Hook Events Reference

| Hook Event | Script | Behavior |
|-----------|--------|---------|
| `sessionStart` | `on-session-start.ps1` | Speaks summary of initial prompt |
| `sessionEnd` | `on-session-end.ps1` | Speaks completion reason |
| `userPromptSubmitted` | `on-prompt-submitted.ps1` | Speaks new instruction summary |
| `postToolUse` | `on-post-tool-use.ps1` | Speaks for interesting tools; silent for noisy |
| `errorOccurred` | `on-error.ps1` | Speaks error name + message; bypasses rate limit |

## Repository Structure

```text
.github/hooks/
├── voice-status.json              # Hook configuration (Copilot hooks v1 protocol)
└── scripts/
    ├── voice-status-config.json   # Voice settings (tool lists, rate limits, voice prefs)
    ├── voice-status-common.ps1    # Shared: TTS, sanitization, rate limiting, dedup, config
    ├── on-session-start.ps1
    ├── on-session-end.ps1
    ├── on-prompt-submitted.ps1
    ├── on-post-tool-use.ps1
    └── on-error.ps1

tests/                             # Pester 5.x test suite
docs/
├── setup.md                       # Step-by-step installation guide
└── testing-guide.md               # Manual testing playbook with sample payloads
```

## Development & Testing

Tests use [Pester 5.x](https://pester.dev/). Install if not present:

```powershell
Install-Module -Name Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck
```

Run all tests:

```powershell
Invoke-Pester -Path tests\ -Output Detailed
```

See [docs/testing-guide.md](docs/testing-guide.md) for manual testing with sample JSON payloads.

## Troubleshooting

**No audio heard:**
- Run the TTS smoke test above
- Check Windows audio output is not muted
- Verify `Add-Type -AssemblyName System.Speech` succeeds in PowerShell

**Hooks not firing (cloud agent):**
- Ensure `.github/hooks/voice-status.json` is committed to the default branch
- Check the Copilot agent session logs for hook errors

**Hooks not firing (CLI):**
- Ensure `.github/hooks/voice-status.json` exists in the repository root
- Run the CLI from the repo root directory

**PowerShell execution policy error:**
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

## License

MIT — see [LICENSE](LICENSE)
