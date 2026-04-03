# Tasks: Copilot Agent Hooks Voice Status

**Input**: Design documents from `/specs/002-copilot-hooks-voice-status/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: Included — Pester 5.x tests are part of the plan (Constitution VII: Tested and Reliable).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Migration & Project Structure)

**Purpose**: Remove TypeScript/Node.js artifacts and establish the new PowerShell + hooks directory structure.

- [ ] T001 Remove TypeScript source and Node.js artifacts: delete src/, dist/, node_modules/, package.json, package-lock.json, tsconfig.json, vitest.config.ts, eslint.config.js, and all tests/*.test.ts files
- [ ] T002 Create hooks directory structure: .github/hooks/scripts/ and tests/ and docs/ directories
- [ ] T003 Create hook configuration file .github/hooks/voice-status.json with version 1 format, mapping sessionStart, sessionEnd, userPromptSubmitted, postToolUse, and errorOccurred to their respective PowerShell scripts in .github/hooks/scripts/ with timeoutSec 10 and cwd "." (per contracts/hook-configuration.md)
- [ ] T004 [P] Create default voice-status-config.json in .github/hooks/scripts/voice-status-config.json with interestingTools, noisyTools, rateLimitMs (3000), dedupWindowMs (10000), ttsTimeoutMs (30000), voiceRate (0), voiceVolume (100) per contracts/voice-status-config.md
- [ ] T005 [P] Update .gitignore to exclude node_modules/, dist/, and add $env:TEMP state files if needed

---

## Phase 2: Foundational (Shared Module)

**Purpose**: Build the core shared PowerShell module that ALL hook scripts depend on. MUST complete before any user story.

**⚠️ CRITICAL**: No hook script can function until this phase is complete.

- [ ] T006 Implement config loading in .github/hooks/scripts/voice-status-common.ps1: function Get-VoiceStatusConfig that reads voice-status-config.json (from script directory), applies env var overrides (VOICE_STATUS_RATE_LIMIT_MS, VOICE_STATUS_DEDUP_WINDOW_MS, VOICE_STATUS_TIMEOUT_MS, VOICE_STATUS_VOLUME, VOICE_STATUS_RATE), clamps values to valid ranges, falls back to built-in defaults if file missing or malformed
- [ ] T007 Implement text sanitization in .github/hooks/scripts/voice-status-common.ps1: function Sanitize-TextForTTS that removes null bytes, strips SSML/XML tags, escapes single quotes (double them), removes double quotes and backticks, strips control characters (except tab/newline/CR), collapses whitespace, trims, and enforces 200-char max length (port from existing src/speech/sanitizer.ts logic)
- [ ] T008 Implement fire-and-forget TTS in .github/hooks/scripts/voice-status-common.ps1: function Invoke-Speech that takes sanitized text and config, builds a PowerShell script block using Add-Type System.Speech.Synthesis with configurable Rate and Volume, launches via Start-Job, and returns immediately without waiting. Include timeout handling for the background job.
- [ ] T009 Implement stdin JSON parser in .github/hooks/scripts/voice-status-common.ps1: function Read-HookPayload that reads stdin via [Console]::In.ReadToEnd(), parses with ConvertFrom-Json, and returns $null on any failure (malformed JSON, empty input) without throwing
- [ ] T010 Implement message summarization in .github/hooks/scripts/voice-status-common.ps1: function Get-ToolSummary that takes toolName, toolArgs (JSON string), and toolResult object, and returns a short spoken message. Must handle: edit → "Edited [filename]", create → "Created [filename]", bash/powershell → detect test results ("N tests passed, M failed"), build output ("Build succeeded"/"Build failed"), lint output, or fall back to "Command completed". Extract filenames from toolArgs JSON path field.
- [ ] T011 [P] Create test helpers in tests/test-helpers.ps1: shared functions for Pester tests including New-MockPayload (generates sample JSON for each event type), Mock-Speech (mocks Invoke-Speech to capture spoken text without audio), Get-SampleToolResult (returns sample toolResult objects for success/failure), and New-TempStateFile (creates/cleans temp state files for test isolation)
- [ ] T012 Write Pester unit tests for config loading in tests/voice-status-common.Tests.ps1: test Get-VoiceStatusConfig with valid JSON, missing file (defaults), malformed JSON (defaults), env var overrides, range clamping (e.g., rateLimitMs below 1000 clamped to 1000), and partial config (missing fields get defaults)
- [ ] T013 Write Pester unit tests for text sanitization in tests/voice-status-common.Tests.ps1: test Sanitize-TextForTTS with normal text, text with single quotes, text with backticks, text with SSML tags, text with null bytes, text over 200 chars (truncated), empty string, control characters, and PowerShell injection attempts (e.g., "; Remove-Item")
- [ ] T014 Write Pester unit tests for message summarization in tests/voice-status-common.Tests.ps1: test Get-ToolSummary for edit (extracts filename), create (extracts filename), bash with test output ("All 15 tests passed" → "15 tests passed"), bash with failure output, bash with generic output ("Command completed"), and unknown tool names

**Checkpoint**: Shared module complete — hook scripts can now be built.

---

## Phase 3: User Story 1 — Hear What the Agent Is Doing Without Watching (Priority: P1) 🎯 MVP

**Goal**: Hook scripts fire on session start, session end, and tool completion, speaking brief summaries via TTS.

**Independent Test**: Pipe sample JSON into each hook script and verify spoken audio output.

### Tests for User Story 1

- [ ] T015 [P] [US1] Write Pester integration test in tests/on-session-start.Tests.ps1: pipe sessionStart JSON with initialPrompt, verify Invoke-Speech called with "Session started. [truncated prompt]". Test with source "new" and "resume". Test with missing/empty initialPrompt (should speak "Session started").
- [ ] T016 [P] [US1] Write Pester integration test in tests/on-session-end.Tests.ps1: pipe sessionEnd JSON with reason "complete", verify Invoke-Speech called with "Session complete". Test all reason values: complete, error, abort, timeout, user_exit.
- [ ] T017 [P] [US1] Write Pester integration test in tests/on-post-tool-use.Tests.ps1: pipe postToolUse JSON with toolName "edit" and success result, verify Invoke-Speech called with "Edited [filename]". Test with bash tool and test output. Test with malformed JSON (silent exit, no crash).

### Implementation for User Story 1

- [ ] T018 [US1] Implement .github/hooks/scripts/on-session-start.ps1: dot-source voice-status-common.ps1, call Read-HookPayload, extract initialPrompt, compose message "Session started. [first 150 chars of prompt]", sanitize, invoke speech. Exit 0 on any failure.
- [ ] T019 [P] [US1] Implement .github/hooks/scripts/on-session-end.ps1: dot-source voice-status-common.ps1, call Read-HookPayload, extract reason, map to spoken text ("Session complete", "Session ended with error", "Session aborted", "Session timed out", "Session ended"), sanitize, invoke speech. Exit 0 on any failure.
- [ ] T020 [US1] Implement .github/hooks/scripts/on-post-tool-use.ps1: dot-source voice-status-common.ps1, call Read-HookPayload, extract toolName/toolArgs/toolResult, call Get-ToolSummary for spoken message, sanitize, invoke speech. Exit 0 on any failure. (No filtering yet — speaks for all tools.)

**Checkpoint**: Core hooks working — session lifecycle and tool completions produce speech. Pipe test JSON to verify.

---

## Phase 4: User Story 2 — Only Hear Meaningful Updates, Not Noise (Priority: P1)

**Goal**: postToolUse hook filters tools into "interesting" (speak) vs "noisy" (silent) using the JSON config.

**Independent Test**: Pipe postToolUse JSON with "view" tool and verify silence; pipe with "edit" tool and verify speech.

### Tests for User Story 2

- [ ] T021 [P] [US2] Write Pester unit tests for tool classification in tests/voice-status-common.Tests.ps1: test Test-IsInterestingTool returns $true for edit, create, bash, powershell, write_powershell, task. Returns $false for view, grep, glob, read_powershell, list_powershell, web_fetch. Returns $false for unrecognized tool names (FR-008). Test with custom config overriding the tool lists.
- [ ] T022 [P] [US2] Update Pester integration test in tests/on-post-tool-use.Tests.ps1: add test cases for noisy tools (view, grep, glob) verifying Invoke-Speech is NOT called. Add test for unrecognized tool name verifying silence.

### Implementation for User Story 2

- [ ] T023 [US2] Implement tool classification in .github/hooks/scripts/voice-status-common.ps1: function Test-IsInterestingTool that takes toolName and config, returns $true if toolName is in config.interestingTools, $false otherwise (unrecognized = noisy per FR-008)
- [ ] T024 [US2] Update .github/hooks/scripts/on-post-tool-use.ps1: add tool filtering — after parsing payload, call Test-IsInterestingTool. If $false, exit 0 immediately without speech. Only proceed to summarize and speak if tool is interesting.

**Checkpoint**: postToolUse now filters noise — "view" is silent, "edit" speaks. Verify with test JSON.

---

## Phase 5: User Story 3 — Prevent Audio Spam During Rapid Operations (Priority: P2)

**Goal**: Rate limiting (default 3s) and deduplication (default 10s) prevent overwhelming audio from rapid hook invocations.

**Independent Test**: Rapid-fire two hook invocations within 3 seconds, verify second is suppressed.

### Tests for User Story 3

- [ ] T025 [P] [US3] Write Pester unit tests for rate limiting in tests/voice-status-common.Tests.ps1: test Test-RateLimited returns $true when lastSpokenAt is within rateLimitMs, returns $false when interval has passed, handles missing state file, handles corrupted state file
- [ ] T026 [P] [US3] Write Pester unit tests for deduplication in tests/voice-status-common.Tests.ps1: test Test-IsDuplicate returns $true for identical message within dedupWindowMs, returns $false for different message, returns $false when window expired, handles missing state file, prunes expired entries on read
- [ ] T027 [P] [US3] Write Pester integration test verifying rate limiting end-to-end: invoke on-session-start.ps1 twice rapidly (< 3s apart), verify Invoke-Speech called only once

### Implementation for User Story 3

- [ ] T028 [US3] Implement rate limiting in .github/hooks/scripts/voice-status-common.ps1: function Test-RateLimited that reads $env:TEMP/voice-status-state.json, compares lastSpokenAt to current time against config.rateLimitMs. Function Update-SpeechState that writes updated lastSpokenAt and recentMessages using atomic write (write temp file then Move-Item). Both use last-write-wins, no locking.
- [ ] T029 [US3] Implement deduplication in .github/hooks/scripts/voice-status-common.ps1: function Test-IsDuplicate that hashes message text (case-insensitive), checks recentMessages array for matching hash within config.dedupWindowMs. Function Add-RecentMessage that appends hash+timestamp. Include cleanup of expired entries on every read.
- [ ] T030 [US3] Wire rate limiting and dedup into all hook scripts: update on-session-start.ps1, on-session-end.ps1, on-post-tool-use.ps1 to call Test-RateLimited and Test-IsDuplicate before Invoke-Speech. If rate limited or duplicate, exit 0 silently. Call Update-SpeechState after successful speech.

**Checkpoint**: Rapid tool calls no longer spam audio — rate limiting and dedup verified via test JSON.

---

## Phase 6: User Story 4 — Hear About Errors Immediately (Priority: P2)

**Goal**: Error hook speaks error name + short description. Errors bypass rate limiting (per clarification).

**Independent Test**: Pipe errorOccurred JSON and verify error is spoken even if within rate limit window.

### Tests for User Story 4

- [ ] T031 [P] [US4] Write Pester integration test in tests/on-error.Tests.ps1: pipe errorOccurred JSON with error.name "TimeoutError" and error.message "Network timeout", verify Invoke-Speech called with "Error: TimeoutError. Network timeout". Test with missing error.name (graceful fallback). Test that rate limiting is bypassed (set lastSpokenAt to now, verify speech still fires).
- [ ] T032 [P] [US4] Write Pester unit test verifying postToolUse with resultType "failure" also speaks error summary and bypasses rate limit

### Implementation for User Story 4

- [ ] T033 [US4] Implement .github/hooks/scripts/on-error.ps1: dot-source voice-status-common.ps1, call Read-HookPayload, extract error.name and error.message, compose "Error: [name]. [message truncated to fit 200 chars]", sanitize, invoke speech. BYPASS rate limiting (do not call Test-RateLimited). Still check dedup. Exit 0 on any failure.
- [ ] T034 [US4] Update .github/hooks/scripts/on-post-tool-use.ps1: when toolResult.resultType is "failure", bypass rate limiting (same as error hook). Compose error-style message from tool result.

**Checkpoint**: Errors are always spoken immediately — verified by piping error JSON right after another message.

---

## Phase 7: User Story 5 — Know When a New Task Begins (Priority: P3)

**Goal**: User prompt submissions trigger a spoken summary of the new instruction.

**Independent Test**: Pipe userPromptSubmitted JSON and verify spoken summary.

### Tests for User Story 5

- [ ] T035 [P] [US5] Write Pester integration test in tests/on-prompt-submitted.Tests.ps1: pipe userPromptSubmitted JSON with prompt "Add unit tests for the login module", verify Invoke-Speech called with "New task: add unit tests for the login module" (truncated if needed). Test with empty prompt (silent exit). Test with very long prompt (truncated to 200 chars total).

### Implementation for User Story 5

- [ ] T036 [US5] Implement .github/hooks/scripts/on-prompt-submitted.ps1: dot-source voice-status-common.ps1, call Read-HookPayload, extract prompt, compose "New task: [first ~180 chars of prompt]", sanitize, check rate limit and dedup, invoke speech. Exit 0 on any failure.

**Checkpoint**: New prompts are announced — verified by piping prompt JSON.

---

## Phase 8: User Story 6 — Configure Voice Behavior via Environment Variables (Priority: P3)

**Goal**: All config values (rate limit, dedup window, TTS rate/volume) can be overridden via env vars.

**Independent Test**: Set VOICE_STATUS_VOLUME=50, invoke any hook, verify speech at 50% volume.

### Tests for User Story 6

- [ ] T037 [P] [US6] Write Pester integration tests in tests/voice-status-common.Tests.ps1: set $env:VOICE_STATUS_RATE_LIMIT_MS="5000", verify Get-VoiceStatusConfig returns rateLimitMs=5000. Set $env:VOICE_STATUS_VOLUME="50", verify voiceVolume=50. Verify env vars override JSON config values. Verify invalid env var values are handled (non-numeric → use default).

### Implementation for User Story 6

- [ ] T038 [US6] Verify and harden env var override logic in .github/hooks/scripts/voice-status-common.ps1 Get-VoiceStatusConfig: ensure all 5 env vars (VOICE_STATUS_RATE_LIMIT_MS, VOICE_STATUS_DEDUP_WINDOW_MS, VOICE_STATUS_TIMEOUT_MS, VOICE_STATUS_VOLUME, VOICE_STATUS_RATE) properly override JSON values, with type validation (parse as int, fall back to JSON/default on failure) and range clamping

**Checkpoint**: Configuration fully customizable via env vars — verified by setting vars and running hooks.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, README rewrite, and final validation across all stories.

- [ ] T039 [P] Rewrite README.md for hooks architecture: project overview, prerequisites (Windows 10+, PowerShell 5.1), installation (copy .github/hooks/ into repo), configuration (JSON config + env vars), what you'll hear (event→message table), hook events reference, troubleshooting, development/testing with Pester, license
- [ ] T040 [P] Create docs/setup.md: step-by-step setup and installation guide covering prerequisites check, installation methods, TTS smoke test, configuration options, activation for cloud agent vs CLI, and troubleshooting common issues (per plan.md deliverables section)
- [ ] T041 [P] Create docs/testing-guide.md: manual testing playbook with 12 copy-pasteable test scenarios — TTS smoke test, each hook event simulation, tool filtering verification, rate limiting test, dedup test, env var override test, and end-to-end Copilot CLI test. Each scenario includes exact JSON payload, expected output, and troubleshooting (per plan.md deliverables section)
- [ ] T042 Run full Pester test suite via Invoke-Pester -Path tests/ and fix any failures
- [ ] T043 Run quickstart.md validation: execute all sample commands from specs/002-copilot-hooks-voice-status/quickstart.md and verify they work end-to-end
- [ ] T044 Final review: verify all hook scripts exit 0 on malformed input, verify no Invoke-Expression usage, verify all text is sanitized before TTS, verify no network calls, verify 200-char message limit enforced everywhere

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Phase 2 — core hook scripts
- **US2 (Phase 4)**: Depends on Phase 2 — can parallel with US1 (different functions) but integrates with on-post-tool-use.ps1 from US1
- **US3 (Phase 5)**: Depends on Phase 3 (needs hooks to exist to wire rate limiting into)
- **US4 (Phase 6)**: Depends on Phase 5 (needs rate limiting to bypass it)
- **US5 (Phase 7)**: Depends on Phase 2 only — can parallel with US1-US4 (different script file)
- **US6 (Phase 8)**: Depends on Phase 2 (config loading already built in T006) — can parallel with most stories
- **Polish (Phase 9)**: Depends on all user stories complete

### User Story Dependencies

- **US1 (P1)**: After Foundational → no other story deps
- **US2 (P1)**: After Foundational → integrates with on-post-tool-use.ps1 from US1
- **US3 (P2)**: After US1 → needs hook scripts to wire rate limiting into
- **US4 (P2)**: After US3 → needs rate limiting to implement bypass
- **US5 (P3)**: After Foundational → independent script, no cross-story deps
- **US6 (P3)**: After Foundational → config loading exists, just hardening

### Within Each User Story

- Tests written FIRST, verified to FAIL before implementation
- Shared module functions before hook scripts
- Core implementation before integration/wiring

### Parallel Opportunities

- T004 + T005 (setup tasks, different files)
- T011 (test helpers) parallel with T006-T010 (shared module functions)
- T012 + T013 + T014 (unit tests for different functions, same file but different Describe blocks)
- T015 + T016 + T017 (integration tests, different files)
- T021 + T022 (US2 tests, different files)
- T025 + T026 + T027 (US3 tests, different files/functions)
- T031 + T032 (US4 tests, different files)
- T039 + T040 + T041 (docs, completely independent files)
- US5 can run fully parallel with US3/US4 (independent script file)

---

## Parallel Example: User Story 1

```text
# After Phase 2 complete, launch US1 tests in parallel:
Task T015: "Integration test for session start in tests/on-session-start.Tests.ps1"
Task T016: "Integration test for session end in tests/on-session-end.Tests.ps1"
Task T017: "Integration test for post-tool-use in tests/on-post-tool-use.Tests.ps1"

# Then implement scripts (T019 can parallel with T018):
Task T018: "Implement on-session-start.ps1"
Task T019: "Implement on-session-end.ps1" [P]
Task T020: "Implement on-post-tool-use.ps1" (after T018 pattern established)
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2 Only)

1. Complete Phase 1: Setup (remove TS, create dirs, config files)
2. Complete Phase 2: Foundational (shared module with TTS, sanitization, config, summarization)
3. Complete Phase 3: US1 (session start/end + basic tool completion speech)
4. Complete Phase 4: US2 (tool filtering — interesting vs noisy)
5. **STOP and VALIDATE**: Pipe test JSON into each hook, verify speech for interesting tools, silence for noisy tools
6. Deploy/demo — system is already useful

### Incremental Delivery

1. Setup + Foundational → Shared module ready
2. US1 → Session lifecycle + tool speech working (MVP core)
3. US2 → Smart filtering eliminates noise (MVP complete)
4. US3 → Rate limiting + dedup (production-ready)
5. US4 → Error bypass (resilient)
6. US5 → Prompt announcements (full feature set)
7. US6 → Config hardening (polished)
8. Polish → Docs, README, validation (release-ready)

---

## Notes

- All scripts MUST exit 0 regardless of internal errors (hooks are non-blocking)
- All text MUST be sanitized before TTS (Constitution V: Security by Default)
- No Invoke-Expression anywhere — use Start-Job with script blocks
- Speech is fire-and-forget via Start-Job — hook exits immediately
- State file uses last-write-wins, no file locking (per clarification)
- Error messages bypass rate limiting but not deduplication (per clarification)
- Unrecognized tool names are treated as noisy/silent (FR-008)
- 200-character hard limit on all spoken messages (FR-015)
