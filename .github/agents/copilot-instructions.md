# mcp-voice-status Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-01-18

## Active Technologies
- PowerShell 5.1 (ships with Windows 10+) + System.Speech.Synthesis (.NET Framework, built into Windows), ConvertFrom-Json (built into PowerShell 5.1) (002-copilot-hooks-voice-status)
- Filesystem-based temp files for rate limit/dedup state (`$env:TEMP/voice-status-state.json`) (002-copilot-hooks-voice-status)

- TypeScript 5.x with strict mode, targeting Node.js 20 LTS + `@modelcontextprotocol/sdk` (MCP protocol), `zod` (validation) (001-mcp-voice-status)

## Project Structure

```text
src/
tests/
```

## Commands

npm test; npm run lint

## Code Style

TypeScript 5.x with strict mode, targeting Node.js 20 LTS: Follow standard conventions

## Recent Changes
- 002-copilot-hooks-voice-status: Added PowerShell 5.1 (ships with Windows 10+) + System.Speech.Synthesis (.NET Framework, built into Windows), ConvertFrom-Json (built into PowerShell 5.1)

- 001-mcp-voice-status: Added TypeScript 5.x with strict mode, targeting Node.js 20 LTS + `@modelcontextprotocol/sdk` (MCP protocol), `zod` (validation)

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
