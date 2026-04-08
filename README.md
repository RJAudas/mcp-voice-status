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

## VS Code Configuration

MCP servers are configured in `mcp.json`. You can add the server to your user configuration or workspace configuration.

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

After configuring VS Code:

1. Press `Ctrl+Shift+P` and run **"MCP: List Servers"**
2. Find `voice-status` and click **Start** (or restart VS Code)
3. Open GitHub Copilot Chat
4. Ask: *"Register call sign 'Copilot' and say hello"*
5. You should hear: **"Copilot: confirm. Hello."**

## Automatic Voice Status (Optional)

By default, you need to explicitly ask the agent to use voice status. To make it automatic, add a **Copilot Instructions file** to your project:

```markdown
<!-- filepath: .github/copilot-instructions.md -->
# Agent Instructions

## Voice Status

You have access to voice status tools. Use them to keep the user informed:

1. At the start of any task, call `register_callsign` with "Copilot"
2. Use `speak_status` to announce:
   - `confirm` — when you start a task
   - `waiting` — when you need user input
   - `done` — when you complete a task
   - `error` — if something fails

Keep spoken messages brief (under 200 characters).
```

This file is automatically loaded by Copilot in that workspace, so the agent will use voice status without being asked.

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
speak_status(phase="done", message="All tests passing.")
→ "Copilot: done. All tests passing."

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
| `done` | Task completed successfully | "Refactoring complete." |
| `error` | Something failed | "Error. Could not parse file." |

## Rate Limiting & Deduplication

The server automatically prevents audio spam:

- **Rate limit**: Max 1 message per 3 seconds per call sign
- **Deduplication**: Identical messages within 10 seconds are skipped

If a message is skipped, the tool returns `spoken: false` with a reason:
- `rate_limited` — wait for cooldown
- `deduplicated` — same message already spoken recently

## Configuration

Environment variables for advanced configuration:

| Variable | Default | Description |
|----------|---------|-------------|
| `MCP_VOICE_RATE_LIMIT_MS` | `3000` | Minimum interval between messages (ms) |
| `MCP_VOICE_DEDUP_WINDOW_MS` | `10000` | Deduplication window (ms) |
| `MCP_VOICE_TTS_TIMEOUT_MS` | `30000` | TTS process timeout (ms) |
| `MCP_VOICE_DEFAULT_CALLSIGN` | — | Default call sign if none registered |

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

## Development

```bash
# Run in development mode (with hot reload)
npm run dev

# Run the source launcher once (no file watching)
npm run start:source

# Run the source launcher with refresh on code changes
npm run start:source:watch

# Run tests
npm test

# Lint code
npm run lint

# Build for production
npm run build
```

## License

MIT License - see [LICENSE](LICENSE) file for details.
