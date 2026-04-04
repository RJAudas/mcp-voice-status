# Setup & Installation Guide

This guide walks you through installing Voice Status Hooks into your repository so that GitHub Copilot speaks brief status updates as it works.

## Step 1: Check Prerequisites

Open a PowerShell 5.1 (or later) terminal and verify:

```powershell
# Check PowerShell version (must be 5.1+)
$PSVersionTable.PSVersion

# Verify System.Speech is available (ships with Windows 10+)
Add-Type -AssemblyName System.Speech
Write-Host "System.Speech: OK"
```

If `Add-Type` fails, you may be on a non-Windows system or a stripped Windows Server image without .NET Framework. Voice Status Hooks require Windows 10/11.

## Step 2: Install

### Option A — Copy into an existing repo

```powershell
# From the voice-status-hooks repo directory:
$targetRepo = "C:\path\to\your-repo"

Copy-Item -Recurse ".github\hooks" "$targetRepo\.github\hooks" -Force
```

### Option B — Clone this repo directly

```powershell
git clone https://github.com/your-org/mcp-voice-status.git
cd mcp-voice-status
# The .github/hooks/ directory is the deliverable — copy it to your repo
```

## Step 3: Verify TTS Works

Run a quick smoke test before committing:

```powershell
# Smoke test — should hear "Voice status hooks ready"
Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$synth.Speak("Voice status hooks ready")
$synth.Dispose()
```

If you hear the phrase, TTS is working.

## Step 4: Configure (Optional)

Edit `.github/hooks/scripts/voice-status-config.json` to customize behavior:

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

**Key settings:**

| Setting | Description | Range/Default |
|---------|-------------|---------------|
| `rateLimitMs` | Minimum ms between spoken messages | 1000–60000, default 3000 |
| `dedupWindowMs` | Suppress identical messages within this window | 1000–300000, default 10000 |
| `voiceVolume` | TTS volume | 0–100, default 100 |
| `voiceRate` | TTS speech rate (negative = slower, positive = faster) | -10 to 10, default 0 |
| `ttsTimeoutMs` | Maximum time a TTS job can run before auto-kill | 5000–120000, default 30000 |

To add a custom tool to the interesting list:
```json
"interestingTools": ["edit", "create", "bash", "powershell", "write_powershell", "task", "my_custom_tool"]
```

### Environment Variable Overrides

For quick per-session tuning without editing the JSON:

```powershell
$env:VOICE_STATUS_VOLUME         = "70"   # 70% volume
$env:VOICE_STATUS_RATE_LIMIT_MS  = "5000" # 5 second cooldown
$env:VOICE_STATUS_RATE           = "2"    # Slightly faster speech
```

## Step 5: Activate

### For Copilot Cloud Agent (Coding Agent)

Hooks must be committed to the **default branch** of your repository:

```powershell
cd your-repo
git add .github/hooks/
git commit -m "Add voice status hooks for Copilot agent"
git push origin main
```

Once pushed, start a new Copilot agent session — you should hear "Session started" when it begins.

### For GitHub Copilot CLI

The CLI loads hooks from the current working directory automatically. No commit required — just ensure the `.github/hooks/voice-status.json` file exists in your repo root:

```powershell
# Verify the hook config is in place
Test-Path ".github\hooks\voice-status.json"  # Should return True

# Start a Copilot CLI session from your repo root
cd your-repo
gh copilot suggest "fix the bug in auth.ts"
```

## Step 6: Troubleshoot

### No audio output

1. **Check Windows audio**: Ensure speakers/headphones are not muted
2. **Run the TTS smoke test** (Step 3 above)
3. **Check PowerShell execution policy**:
   ```powershell
   Get-ExecutionPolicy -Scope CurrentUser
   # If "Restricted", run:
   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
   ```

### Hooks not firing (cloud agent)

- Verify `.github/hooks/voice-status.json` is on the default branch: `git log --oneline -- .github/hooks/voice-status.json`
- Check Copilot agent session output for hook errors
- Ensure `timeoutSec` in the JSON config is not too low (default 10s is safe)

### Hooks not firing (CLI)

- Run `gh copilot` from the repo root directory (not a subdirectory)
- Verify the hooks file exists: `Test-Path ".github\hooks\voice-status.json"`

### PowerShell script won't run

The hook configuration in this repo launches scripts with `-NoProfile -ExecutionPolicy Bypass`, so normal hook execution should work even if `CurrentUser` is `Restricted`. If you run the scripts directly in your own terminal, PowerShell will still apply your local policy.

```powershell
# Allow local scripts to run
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

# Or unblock specific files if downloaded from internet
Unblock-File -Path ".github\hooks\scripts\*.ps1"
```

### Speech sounds garbled or too fast/slow

Edit `voice-status-config.json` and adjust `voiceRate` (-10 to 10, default 0):
```json
"voiceRate": -2
```

### State file issues (duplicate/missing speech)

The rate limiter/dedup state lives at `$env:TEMP\voice-status-state.json`. To reset:
```powershell
Remove-Item "$env:TEMP\voice-status-state.json" -Force -ErrorAction SilentlyContinue
```
