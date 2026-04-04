# Contract: Hook Configuration Schema

**File**: `.github/hooks/voice-status.json`
**Protocol**: GitHub Copilot Hooks v1

## Schema

```json
{
  "version": 1,
  "hooks": {
    "sessionStart": [
      {
        "type": "command",
        "powershell": "powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File .github/hooks/scripts/on-session-start.ps1",
        "cwd": ".",
        "timeoutSec": 10
      }
    ],
    "sessionEnd": [
      {
        "type": "command",
        "powershell": "powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File .github/hooks/scripts/on-session-end.ps1",
        "cwd": ".",
        "timeoutSec": 10
      }
    ],
    "userPromptSubmitted": [
      {
        "type": "command",
        "powershell": "powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File .github/hooks/scripts/on-prompt-submitted.ps1",
        "cwd": ".",
        "timeoutSec": 10
      }
    ],
    "postToolUse": [
      {
        "type": "command",
        "powershell": "powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File .github/hooks/scripts/on-post-tool-use.ps1",
        "cwd": ".",
        "timeoutSec": 10
      }
    ],
    "errorOccurred": [
      {
        "type": "command",
        "powershell": "powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File .github/hooks/scripts/on-error.ps1",
        "cwd": ".",
        "timeoutSec": 10
      }
    ]
  }
}
```

## Notes

- `timeoutSec: 10` is aggressive but safe — scripts launch TTS as a background job and exit immediately
- Use `-NoProfile` to avoid failures caused by a blocked user profile script during hook startup
- Use `-ExecutionPolicy Bypass` so hook execution does not depend on the user's `CurrentUser` policy
- `cwd: "."` means scripts resolve relative to the repository root
- No `bash` keys are provided — this is Windows-only
- No `preToolUse` hook is used — we only need post-execution information
- Each event maps to exactly one hook entry (no multi-hook chaining needed)
