# Quickstart: MCP Voice Status Server

Get audible status updates from VS Code agents in under 5 minutes.

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

## VS Code Configuration

Add the server to your VS Code MCP settings:

### For GitHub Copilot

Edit your VS Code `settings.json`:

```json
{
  "github.copilot.chat.mcpServers": {
    "voice-status": {
      "command": "mcp-voice-status",
      "args": []
    }
  }
}
```

### Alternative: Using npx

If you don't want to install globally:

```json
{
  "github.copilot.chat.mcpServers": {
    "voice-status": {
      "command": "npx",
      "args": ["mcp-voice-status"]
    }
  }
}
```

### Alternative: Using node directly

Point to the built JavaScript file:

```json
{
  "github.copilot.chat.mcpServers": {
    "voice-status": {
      "command": "node",
      "args": ["C:/path/to/mcp-voice-status/dist/index.js"]
    }
  }
}
```

## Quick Test

After configuring VS Code, restart the editor and try:

1. Open GitHub Copilot Chat
2. Ask: *"Register call sign 'Copilot' and say hello"*
3. You should hear: **"Copilot: confirm. Hello."**

## Tool Reference

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

## Troubleshooting

### No audio output

1. Check Windows volume and audio output device
2. Verify PowerShell TTS works:
   ```powershell
   Add-Type -AssemblyName System.Speech
   (New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak("Test")
   ```

### "No call sign registered" error

Call `register_callsign` before `speak_status`. The call sign persists for the session.

### Server not appearing in VS Code

1. Check that the command path is correct in settings
2. Restart VS Code after changing MCP settings
3. Check VS Code Output panel for MCP errors

### Messages cut off or not speaking

- Ensure messages are under 200 characters
- Check that messages contain actual text (not just whitespace)

## Development

```bash
# Run in development mode (with hot reload)
npm run dev

# Run tests
npm test

# Lint code
npm run lint

# Build for production
npm run build
```

## Configuration Options

Environment variables for advanced configuration:

| Variable | Default | Description |
|----------|---------|-------------|
| `MCP_VOICE_RATE_LIMIT_MS` | `3000` | Minimum interval between messages (ms) |
| `MCP_VOICE_DEDUP_WINDOW_MS` | `10000` | Deduplication window (ms) |
| `MCP_VOICE_TTS_TIMEOUT_MS` | `30000` | TTS process timeout (ms) |
| `MCP_VOICE_DEFAULT_CALLSIGN` | — | Default call sign if none registered |

## License

MIT
