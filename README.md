# MCP Voice Status Server

A local-only MCP (Model Context Protocol) server that enables VS Code agents to emit short spoken status messages via Windows text-to-speech.

## Features

- 🗣️ **Spoken Status Updates** - Hear what your AI agent is doing without watching the screen
- 🎯 **Call Sign Identification** - Each agent registers a unique identifier for multi-agent clarity
- 🚦 **Status Phases** - Structured updates: confirm, waiting, blocked, done, error
- ⏱️ **Rate Limiting** - Prevents audio spam (configurable cooldown per call sign)
- 🔄 **Deduplication** - Automatically skips repeated identical messages
- 🔒 **Local Only** - All processing happens locally via Windows System.Speech

## Prerequisites

- **Windows 10/11** (required for `System.Speech`)
- **Node.js 20+** (LTS recommended)
- **VS Code** with an MCP-compatible agent (GitHub Copilot, etc.)
- **Audio output** configured and working

## Installation

### Option 1: Install from npm (recommended)

```bash
npm install -g mcp-voice-status
```

### Option 2: Build from source

```bash
git clone https://github.com/your-username/mcp-voice-status.git
cd mcp-voice-status
npm install
npm run build
npm link  # Makes 'mcp-voice-status' available globally
```

### Option 3: Run from source with a launcher script

Use the checked-in PowerShell launcher when you want VS Code to run the server straight from `src` instead of `dist`.

Before using the launcher script:

1. Install **Node.js 20+**
2. Run `npm install` in the repo so `tsx` and the other local dependencies exist
3. Run the script from **Windows PowerShell 5.1+** or **PowerShell 7+**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-VoiceMcpFromSource.ps1
```

Add `-Watch` to restart the source server when files under `src` change:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-VoiceMcpFromSource.ps1 -Watch
```

### Option 4: Configure VS Code chat and Copilot CLI automatically

Use the checked-in installer script to add the required MCP entries and ensure the repo instructions file exists:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-VoiceStatusClientConfig.ps1
```

By default this script:

1. Creates or updates `.vscode\mcp.json` for VS Code chat in this repo
2. Creates or updates `~\.copilot\mcp-config.json` for Copilot CLI
3. Ensures `.github\copilot-instructions.md` exists in the repo

Useful options:

```powershell
# Preview the files that would be changed
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-VoiceStatusClientConfig.ps1 -DryRun

# Add the server to VS Code user config as well as the workspace config
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-VoiceStatusClientConfig.ps1 -VsCodeTarget Both

# Use the source watcher for the registered server command
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-VoiceStatusClientConfig.ps1 -Watch
```

## VS Code Configuration

MCP servers are configured in `mcp.json`. You can add the server to your user configuration or workspace configuration.

If you are working from this repository, the fastest path is to run `npm run setup:client` or `.\scripts\Install-VoiceStatusClientConfig.ps1`, which writes `.vscode\mcp.json` for you.

### Option 1: User Configuration (recommended)

1. Press `Ctrl+Shift+P` and run **"MCP: Open User Configuration"**
2. Add the voice-status server to the `servers` object:

```json
{
  "servers": {
    "voice-status": {
      "type": "stdio",
      "command": "node",
      "args": ["C:/path/to/mcp-voice-status/dist/index.js"]
    }
  }
}
```

### Option 2: Workspace Configuration

1. Press `Ctrl+Shift+P` and run **"MCP: Open Workspace Folder Configuration"**
2. Add the same configuration as above

### Option 3: Using npx (no global install)

```json
{
  "servers": {
    "voice-status": {
      "type": "stdio",
      "command": "npx",
      "args": ["mcp-voice-status"]
    }
  }
}
```

### Option 4: Using global install

If installed globally via `npm install -g mcp-voice-status`:

```json
{
  "servers": {
    "voice-status": {
      "type": "stdio",
      "command": "mcp-voice-status"
    }
  }
}
```

### Option 5: Run from source in VS Code

Point VS Code at the launcher script if you want to develop against the source tree without rebuilding `dist`:

```json
{
  "servers": {
    "voice-status": {
      "type": "stdio",
      "command": "powershell.exe",
      "args": [
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "C:\\path\\to\\mcp-voice-status\\scripts\\Start-VoiceMcpFromSource.ps1",
        "-Watch"
      ]
    }
  }
}
```

`-Watch` restarts the source-backed server whenever files under `src` change. During active development, that is usually enough; if VS Code keeps an old MCP session around after a restart, run **"MCP: List Servers"** and restart `voice-status`.

## Quick Test

After configuring VS Code and, if desired, Copilot CLI:

1. Press `Ctrl+Shift+P` and run **"MCP: List Servers"**
2. Find `voice-status` and click **Start** (or restart VS Code)
3. Open GitHub Copilot Chat
4. Ask: *"Register call sign 'Copilot' and say hello"*
5. You should hear: **"Copilot: confirm. Hello."**

For Copilot CLI, restart the CLI after updating `~/.copilot/mcp-config.json`, then run `/mcp show voice-status` to confirm the server is available.

## Automatic Voice Status (Optional)

The recommended approach is **instruction-driven, context-aware callouts**. Do **not** rely on hooks for prompt-progress speech; hooks fire without enough reasoning context and tend to produce worse callouts.

The default behavior should cover both halves of a good status update:

1. brief nudges while work is in progress
2. a concise spoken outcome or answer when the task completes successfully

This repo now ships two checked-in pieces for automatic behavior:

1. `.github/copilot-instructions.md` teaches the agent when spoken updates are useful
2. `voice-status.config.json` provides shared defaults for both the agent-facing behavior and the server runtime

The instructions file should look like this:

```markdown
<!-- filepath: .github/copilot-instructions.md -->
# Agent Instructions

## Voice Status

You have access to voice status tools. Use them to keep the user informed:

1. Before using voice status, check `voice-status.config.json` in the repo root if it exists and honor its `automation` settings.
2. At the start of a meaningful task, call `register_callsign` with the configured call sign (default: "Copilot").
3. Use `speak_status` only for contextual callouts that help the user follow progress and outcome:
   - `confirm` when you start a meaningful task or hit a real milestone
   - `waiting` when you need user input
   - `blocked` when an external dependency or constraint is stopping progress
   - `done` when the task is complete; when there is a concrete result or answer, prefer speaking that concise result summary in the `done` callout instead of only saying the task is complete
   - `error` when something fails
4. Do **not** narrate every tool call, file read, or minor step unless the config explicitly allows low-value tool updates.
5. When completion and outcome narration are enabled, successful tasks should end with a `done` callout. Use a generic completion line only if the actual result cannot be stated clearly within the message limit.
6. Keep callouts factual, brief, and timely. Prefer silence over noisy commentary.

Keep spoken messages brief and under 200 characters.
```

This file is automatically loaded by Copilot in that workspace, so the agent can make better, context-aware decisions about when to speak.

### Shared `voice-status.config.json`

The checked-in config file is the single source of truth for default behavior:

```json
{
  "speech": {
    "defaultCallSign": "Copilot",
    "rateLimitMs": 3000,
    "dedupWindowMs": 10000,
    "timeoutMs": 30000,
    "rate": 0,
    "volume": 100
  },
  "automation": {
    "enabled": true,
    "mode": "instructions",
    "callSign": "Copilot",
    "callouts": {
      "taskStart": true,
      "progressMilestones": true,
      "waiting": true,
      "completion": true,
      "outcomeNarration": true,
      "errors": true,
      "lowValueToolUpdates": false
    }
  }
}
```

`speech` settings are consumed by the server at startup. `automation` settings are intended for Copilot instructions and for future settings UI work, so one config surface can control both sides. `outcomeNarration` makes the completion expectation explicit: when a task has a concrete answer, the `done` callout should usually say the answer, not just announce completion.

## Tools

### `register_callsign`

Register an agent identifier before speaking.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `callSign` | string | Yes | Alphanumeric + hyphens, 1-20 chars |

**Example:**
```
Register call sign "Claude"
```

### `speak_status`

Speak a status message.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `phase` | enum | Yes | `confirm`, `waiting`, `blocked`, `done`, `error` |
| `message` | string | Yes | 1-2 sentences, max 200 chars |
| `callSign` | string | No | Override the registered call sign |

**Examples:**
```
# Acknowledge starting work
speak_status(phase="confirm", message="Starting code review.")
→ "Copilot: confirm. Starting code review."

# Report completion
speak_status(phase="done", message="Main entrypoint: src\\index.ts, published as dist\\index.js.")
→ "Copilot: done. Main entrypoint: src\index.ts, published as dist\index.js."

# Report an error
speak_status(phase="error", message="Build failed. Missing dependency.")
→ "Copilot: error. Build failed. Missing dependency."
```

## Status Phases

| Phase | When to Use | Example |
|-------|-------------|---------|
| `confirm` | Acknowledge receipt of instruction | "Starting code review." |
| `waiting` | Waiting for user input or approval | "Waiting for your confirmation." |
| `blocked` | External dependency blocking progress | "Blocked on file access." |
| `done` | Task completed successfully; prefer the concise result or answer | "Main entrypoint: src\index.ts, published as dist\index.js." |
| `error` | Something failed | "Error. Could not parse file." |

## Rate Limiting & Deduplication

The server automatically prevents audio spam:

- **Rate limit**: Max 1 message per 3 seconds per call sign
- **Deduplication**: Identical messages within 10 seconds are skipped

If a message is skipped, the tool returns `spoken: false` with a reason:
- `rate_limited` — wait for cooldown
- `deduplicated` — same message already spoken recently

## Configuration

Configuration precedence is:

1. Built-in defaults
2. `voice-status.config.json`
3. Environment variables

Environment variables for advanced configuration:

| Variable | Default | Description |
|----------|---------|-------------|
| `MCP_VOICE_RATE_LIMIT_MS` | `3000` | Minimum interval between messages (ms) |
| `MCP_VOICE_DEDUP_WINDOW_MS` | `10000` | Deduplication window (ms) |
| `MCP_VOICE_TTS_TIMEOUT_MS` | `30000` | TTS process timeout (ms) |
| `MCP_VOICE_TTS_RATE` | `0` | Windows TTS rate (`-10` to `10`) |
| `MCP_VOICE_TTS_VOLUME` | `100` | Windows TTS volume (`0` to `100`) |
| `MCP_VOICE_DEFAULT_CALLSIGN` | `Copilot` in config | Default call sign if none registered |
| `MCP_VOICE_CONFIG_PATH` | `voice-status.config.json` in current working directory | Override the config file location |

## Troubleshooting

### No audio output

1. Check Windows volume and audio output device
2. Verify PowerShell TTS works:
   ```powershell
   Add-Type -AssemblyName System.Speech
   (New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak("Copilot confirm. Hello!")
   ```
   If you hear "Copilot confirm. Hello!" then TTS is working and the issue is with the MCP server connection.

### "No call sign registered" error

Call `register_callsign` before `speak_status`. The call sign persists for the session.

If you want automatic contextual callouts, make sure `.github/copilot-instructions.md` is present and that `voice-status.config.json` has automation enabled with a default call sign.

### Server not appearing in VS Code

1. MCP servers are configured in `mcp.json`, **not** `settings.json`
2. Run `Ctrl+Shift+P` → **"MCP: Open User Configuration"** to edit your config
3. Run `Ctrl+Shift+P` → **"MCP: List Servers"** to see available servers
4. Start the server from the list, or restart VS Code
5. Check VS Code Output panel (select "MCP" from dropdown) for errors

> **Note:** The old `github.copilot.chat.mcpServers` setting in `settings.json` is deprecated. Use `mcp.json` instead.

### Messages cut off or not speaking

- Ensure messages are under 200 characters
- Check that messages contain actual text (not just whitespace)
- If using a custom config file location, verify `MCP_VOICE_CONFIG_PATH` points at a valid JSON file

## Development

```bash
# Run in development mode (with hot reload)
npm run dev

# Run the source launcher once (no file watching)
npm run start:source

# Run the source launcher with refresh on code changes
npm run start:source:watch

# Write VS Code workspace MCP config + Copilot CLI MCP config
npm run setup:client

# Show the launcher's resolved Node/config settings without starting the server
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-VoiceMcpFromSource.ps1 -DryRun

# Run tests
npm test

# Lint code
npm run lint

# Build for production
npm run build
```

## License

MIT License - see [LICENSE](LICENSE) file for details.
