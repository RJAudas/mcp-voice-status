# Implementation Plan: Copilot Agent Hooks Voice Status

**Branch**: `002-copilot-hooks-voice-status` | **Date**: 2026-04-03 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/002-copilot-hooks-voice-status/spec.md`

## Summary

Pivot the mcp-voice-status project from a TypeScript MCP server to a pure PowerShell + JSON hooks architecture. GitHub Copilot agent hooks fire automatically at lifecycle points (session start/end, tool use, prompts, errors), invoking PowerShell scripts that speak brief status summaries via Windows System.Speech. Zero agent cooperation needed. The existing TTS logic, sanitization, rate limiting, and deduplication are adapted from TypeScript into standalone PowerShell scripts.

## Technical Context

**Language/Version**: PowerShell 5.1 (ships with Windows 10+)
**Primary Dependencies**: System.Speech.Synthesis (.NET Framework, built into Windows), ConvertFrom-Json (built into PowerShell 5.1)
**Storage**: Filesystem-based temp files for rate limit/dedup state (`$env:TEMP/voice-status-state.json`)
**Testing**: Pester 5.x (PowerShell testing framework)
**Target Platform**: Windows 10/11 with PowerShell 5.1
**Project Type**: Single project — hook configuration + PowerShell scripts
**Performance Goals**: Hook script exits within 500ms (speech fires asynchronously); no blocking of agent workflow
**Constraints**: Zero network calls; no Node.js/npm/TypeScript in final deliverable; all text sanitized before TTS; messages under 200 chars
**Scale/Scope**: Single-developer local tool; ~8 PowerShell scripts + 1 JSON hook config + 1 JSON settings config

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Zero-Friction Adoption | ✅ PASS | Copy `.github/hooks/` into repo. No installers, no PATH edits. JSON config with defaults. Two JSON files exist: `voice-status.json` is protocol-required Copilot hooks infrastructure (not user-edited config); `voice-status-config.json` is the single user-facing settings file per Principle I.4. |
| II. Agent-Invisible | ✅ PASS | Hooks fire automatically. Zero agent cooperation required. No system prompt changes. |
| III. Local-Only and Private | ✅ PASS | All processing on-device. Zero network calls. Temp state files only, no persistent data beyond session. |
| IV. Audio-First UX | ✅ PASS | Messages ≤200 chars, 1-2 sentences. Rate limiting (3s default, min 1s). Deduplication (10s window). Silence over noise as default. |
| V. Security by Default | ✅ PASS | All input sanitized. No Invoke-Expression. Shell metacharacters stripped. Spawned PowerShell processes only. No elevated privileges. |
| VI. Windows-Native | ✅ PASS | PowerShell 5.1 + System.Speech only. No external TTS libraries. Separate PS process for TTS. 30s timeout with auto-kill. |
| VII. Tested and Reliable | ✅ PASS | Pester tests for sanitization, rate limiting, dedup, tool classification. Integration tests piping JSON into scripts. Silent failure, no crashes. |
| VIII. Keep It Small | ✅ PASS | ~8 scripts, 1 hook config, 1 settings JSON. No framework. Configuration over code. |

All gates pass. No violations to justify.

## Project Structure

### Documentation (this feature)

```text
specs/002-copilot-hooks-voice-status/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (hook payloads + config schemas)
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
.github/
└── hooks/
    ├── voice-status.json          # Hook configuration (version 1 format)
    └── scripts/
        ├── voice-status-config.json   # Voice status settings (tool classification, rate limits, voice prefs)
        ├── voice-status-common.ps1    # Shared module: TTS, sanitization, rate limiting, dedup, config
        ├── on-session-start.ps1       # sessionStart hook handler
        ├── on-session-end.ps1         # sessionEnd hook handler
        ├── on-prompt-submitted.ps1    # userPromptSubmitted hook handler
        ├── on-post-tool-use.ps1       # postToolUse hook handler
        └── on-error.ps1              # errorOccurred hook handler

tests/
├── voice-status-common.Tests.ps1  # Unit tests: sanitization, rate limiting, dedup, config loading
├── on-session-start.Tests.ps1     # Integration test for session start hook
├── on-session-end.Tests.ps1       # Integration test for session end hook
├── on-prompt-submitted.Tests.ps1  # Integration test for prompt submitted hook
├── on-post-tool-use.Tests.ps1     # Integration test for post-tool-use hook
├── on-error.Tests.ps1             # Integration test for error hook
└── test-helpers.ps1               # Shared test utilities (mock TTS, sample payloads)

docs/
├── setup.md                       # Setup & installation guide (step-by-step)
└── testing-guide.md               # Manual testing playbook with sample JSON payloads
```

**Structure Decision**: Single project with hooks config under `.github/hooks/` (standard Copilot hooks location) and scripts as a sibling directory. Tests under `tests/` at repo root using Pester conventions.

### Files to remove (migration cleanup)

```text
src/                    # All TypeScript source
dist/                   # Build output
node_modules/           # Node dependencies
package.json            # Node config
package-lock.json       # Node lockfile
tsconfig.json           # TypeScript config
vitest.config.ts        # Vitest config
eslint.config.js        # ESLint config
tests/*.test.ts         # Existing vitest tests (replaced by Pester)
```

### Files to keep and update

```text
README.md               # Rewrite for hooks architecture
LICENSE                  # Keep as-is (MIT)
docs/setup.md           # NEW: Step-by-step setup & installation guide
docs/testing-guide.md   # NEW: Manual testing playbook with sample payloads for each hook
.github/agents/         # Update copilot-instructions.md
```

## Deliverable: Setup & Testing Documentation

Two documentation files will be created as part of the implementation to ensure the system is testable end-to-end after build:

### `docs/setup.md` — Setup & Installation Guide

Step-by-step instructions covering:
1. **Prerequisites check** — Verify PowerShell 5.1 and System.Speech are available
2. **Installation** — Copy `.github/hooks/` directory into target repo (or clone this repo)
3. **Verification** — Run a quick TTS smoke test to confirm audio works
4. **Configuration** — How to edit `voice-status-config.json` and/or set environment variables
5. **Activation** — Commit hooks to default branch (cloud agent) or verify cwd loading (CLI)
6. **Troubleshooting** — Common issues (no audio, hooks not firing, timeout errors) with solutions

### `docs/testing-guide.md` — Manual Testing Playbook

A hands-on testing guide with copy-pasteable PowerShell commands that simulate each hook event:
1. **TTS smoke test** — Verify System.Speech works: speak a test phrase
2. **Session start** — Pipe sample `sessionStart` JSON into `on-session-start.ps1`, verify spoken output
3. **User prompt** — Pipe sample `userPromptSubmitted` JSON, verify summary is spoken
4. **Tool use (interesting)** — Pipe `postToolUse` JSON with `edit` tool, verify "Edited filename" spoken
5. **Tool use (noisy)** — Pipe `postToolUse` JSON with `view` tool, verify silence
6. **Tool use (bash with test output)** — Pipe `postToolUse` with test result output, verify summary
7. **Error occurred** — Pipe `errorOccurred` JSON, verify error is spoken (and bypasses rate limit)
8. **Session end** — Pipe `sessionEnd` JSON with various reasons, verify spoken output
9. **Rate limiting** — Rapid-fire two events within 3 seconds, verify second is suppressed
10. **Deduplication** — Send identical messages twice within 10 seconds, verify second is suppressed
11. **Configuration override** — Set env vars, re-run tests, verify new values take effect
12. **End-to-end** — Start an actual Copilot CLI session in a test repo and confirm hooks fire live

Each test includes:
- The exact JSON payload to pipe
- The expected spoken output (or expected silence)
- How to verify success (audio heard vs. no audio)
- Troubleshooting if it doesn't work

## Complexity Tracking

No constitution violations. Table not needed.
