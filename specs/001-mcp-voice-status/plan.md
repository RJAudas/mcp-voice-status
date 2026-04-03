# Implementation Plan: MCP Voice Status Server

**Branch**: `001-mcp-voice-status` | **Date**: 2026-01-18 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-mcp-voice-status/spec.md`

## Summary

A minimal MCP server exposing two tools (`register_callsign`, `speak_status`) that enables VS Code agents to emit short spoken status messages via Windows text-to-speech. The server uses Node.js + TypeScript with the MCP SDK, communicates via stdio, and includes rate limiting, message deduplication, and a sequential speech queue to prevent audio overlap.

## Technical Context

**Language/Version**: TypeScript 5.x with strict mode, targeting Node.js 20 LTS  
**Primary Dependencies**: `@modelcontextprotocol/sdk` (MCP protocol), `zod` (validation)  
**TTS Engine**: PowerShell 5.1 with `System.Speech.Synthesis` (Windows built-in)  
**Storage**: N/A (in-memory state only; no persistence required)  
**Testing**: Vitest for unit and integration tests  
**Target Platform**: Windows 10/11 with Node.js 20+  
**Project Type**: Single project (stdio CLI server)  
**Performance Goals**: <500ms from tool call to speech start; <1s tool response time  
**Constraints**: Zero network calls; <50MB memory; single-threaded speech queue  
**Scale/Scope**: Single-user local tool; ~500 LOC excluding tests

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| **I. Windows-First, Local-Only** | ✅ PASS | PowerShell 5.1 + System.Speech; no network calls |
| **II. Agent Call Sign Protocol** | ✅ PASS | `register_callsign` tool + per-call override; rejects if no call sign |
| **III. Structured Status Phases** | ✅ PASS | Five phases: confirm, waiting, blocked, done, error |
| **IV. Rate Limiting** | ✅ PASS | Default 3s per call sign; configurable minimum 1s |
| **V. Security-First Design** | ✅ PASS | Input validation via Zod; sanitized TTS; no shell injection |
| **VI. Minimal Dependencies** | ✅ PASS | Only MCP SDK + Zod runtime deps; Vitest dev-only |
| **VII. Simplicity & YAGNI** | ✅ PASS | Two tools only; no premature abstraction |

**Security Requirements Compliance**:
- Process isolation: ✅ Spawns separate PowerShell process per utterance
- Timeout enforcement: ✅ 30s default timeout; kills hung processes
- Logging: ✅ Local logging with timestamp, call sign, phase, message hash
- No secrets persistence: ✅ No secrets stored

### Post-Design Re-evaluation (Phase 1 Complete)

**Date**: 2026-01-18

All principles remain satisfied after design phase:

| Artifact | Constitution Compliance |
|----------|------------------------|
| [data-model.md](data-model.md) | ✅ Types are minimal; no over-engineering |
| [contracts/tools.json](contracts/tools.json) | ✅ Two tools only; validates call sign per II |
| [research.md](research.md) | ✅ All decisions align with principles |
| [quickstart.md](quickstart.md) | ✅ Documents local-only setup |

**Verdict**: ✅ **PASS** — Ready for Phase 2 task generation

## Project Structure

### Documentation (this feature)

```text
specs/001-mcp-voice-status/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (MCP tool schemas)
│   └── tools.json       # MCP tool definitions
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
src/
├── index.ts             # Entry point: MCP server setup + stdio transport
├── tools/
│   ├── register-callsign.ts  # Tool: register agent call sign
│   └── speak-status.ts       # Tool: speak status message
├── speech/
│   ├── queue.ts              # Sequential speech queue
│   ├── tts.ts                # PowerShell TTS wrapper
│   └── sanitizer.ts          # Input sanitization for TTS
├── middleware/
│   ├── rate-limiter.ts       # Per-callsign rate limiting
│   └── deduplicator.ts       # Message deduplication
├── validation/
│   └── schemas.ts            # Zod schemas for tool inputs
└── types.ts                  # Shared TypeScript interfaces

tests/
├── unit/
│   ├── sanitizer.test.ts
│   ├── rate-limiter.test.ts
│   ├── deduplicator.test.ts
│   └── schemas.test.ts
└── integration/
    ├── speak-status.test.ts
    └── register-callsign.test.ts
```

**Structure Decision**: Single project layout. The server is a self-contained stdio process with no frontend/backend split. Source organized by responsibility (tools, speech, middleware, validation) for clarity without over-abstraction.

## Complexity Tracking

> No Constitution violations requiring justification. All principles satisfied.
