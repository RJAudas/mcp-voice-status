# Tasks: MCP Voice Status Server

**Input**: Design documents from `/specs/001-mcp-voice-status/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅

**Tests**: Basic unit tests included for core validation and middleware logic.

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: User story label (US1, US2, US3, US4)
- Exact file paths included in all descriptions

---

## Phase 1: Setup (Project Initialization)

**Purpose**: Initialize Node.js/TypeScript project with MCP SDK

- [x] T001 Create project structure with src/, tests/unit/, tests/integration/ directories
- [x] T002 Initialize package.json with name "mcp-voice-status", type "module", Node 20+ engine
- [x] T003 [P] Add runtime dependencies: @modelcontextprotocol/sdk, zod
- [x] T004 [P] Add dev dependencies: typescript, vitest, eslint, @types/node, tsx
- [x] T005 [P] Create tsconfig.json with strict mode, ES2022 target, NodeNext module resolution
- [x] T006 [P] Create .eslintrc.cjs with TypeScript rules
- [x] T007 [P] Create .gitignore for node_modules, dist, .env
- [x] T008 Add npm scripts: build, start, dev, test, lint in package.json

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core types, validation schemas, and TTS infrastructure required by ALL user stories

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T009 Create shared types and constants in src/types.ts (StatusPhase, CallSignConfig, all interfaces from data-model.md)
- [x] T010 [P] Create Zod validation schemas in src/validation/schemas.ts (callSignSchema, speakStatusSchema)
- [x] T011 [P] Create text sanitizer in src/speech/sanitizer.ts (remove SSML, escape quotes, control chars)
- [x] T012 Create PowerShell TTS wrapper in src/speech/tts.ts (execFile with timeout, windowsHide)
- [x] T013 Create speech queue in src/speech/queue.ts (FIFO, promise-based, single processing)
- [x] T014 Create MCP server entry point skeleton in src/index.ts (McpServer + StdioServerTransport setup)

**Checkpoint**: Foundation ready — TTS can speak text, validation schemas defined

---

## Phase 3: User Story 1 - Receive Audible Status (Priority: P1) 🎯 MVP

**Goal**: Agent can register a call sign and speak status messages with correct "[CallSign]: [phase]. [message]" format

**Independent Test**: Run server, call register_callsign, call speak_status, verify audio output with correct prefix

### Unit Tests for User Story 1

- [x] T015 [P] [US1] Unit test for sanitizer in tests/unit/sanitizer.test.ts (SSML removal, quote escaping, length limits)
- [x] T016 [P] [US1] Unit test for Zod schemas in tests/unit/schemas.test.ts (valid/invalid call signs, phases, messages)

### Implementation for User Story 1

- [x] T017 [US1] Implement register_callsign tool in src/tools/register-callsign.ts (validate, store, return response)
- [x] T018 [US1] Implement speak_status tool in src/tools/speak-status.ts (validate, format message, queue speech)
- [x] T019 [US1] Register both tools with MCP server in src/index.ts
- [x] T020 [US1] Add graceful shutdown handling (SIGINT/SIGTERM) in src/index.ts
- [x] T021 [US1] Add console.error logging for all operations (no stdout)

**Checkpoint**: MVP complete — can register call sign and hear spoken status messages

---

## Phase 4: User Story 2 - Rate Limiting (Priority: P2)

**Goal**: Prevent audio spam by enforcing minimum interval between messages per call sign

**Independent Test**: Call speak_status rapidly 3 times, verify only first speaks, others return rate_limited

### Unit Tests for User Story 2

- [x] T022 [P] [US2] Unit test for rate limiter in tests/unit/rate-limiter.test.ts (canSpeak, cooldown calculation, per-callsign isolation)

### Implementation for User Story 2

- [x] T023 [US2] Create rate limiter in src/middleware/rate-limiter.ts (per-callsign Map, configurable interval)
- [x] T024 [US2] Integrate rate limiter into speak_status tool in src/tools/speak-status.ts
- [x] T025 [US2] Return skippedReason: "rate_limited" and cooldownMs when rate limited

**Checkpoint**: Rate limiting active — rapid calls are throttled with informative response

---

## Phase 5: User Story 3 - Deduplication (Priority: P2)

**Goal**: Skip identical consecutive messages within configurable time window

**Independent Test**: Call speak_status with same message twice within 10s, verify only first speaks

### Unit Tests for User Story 3

- [x] T026 [P] [US3] Unit test for deduplicator in tests/unit/deduplicator.test.ts (isDuplicate, TTL expiry, hash-based comparison)

### Implementation for User Story 3

- [x] T027 [US3] Create deduplicator in src/middleware/deduplicator.ts (hash-based cache, per-callsign, configurable window)
- [x] T028 [US3] Integrate deduplicator into speak_status tool in src/tools/speak-status.ts
- [x] T029 [US3] Return skippedReason: "deduplicated" when duplicate detected

**Checkpoint**: Deduplication active — repeated messages are silently filtered

---

## Phase 6: User Story 4 - Call Sign Identification (Priority: P3)

**Goal**: Configurable call sign with per-call override and rejection when missing

**Independent Test**: Call speak_status without registering, verify no_callsign error; then with override, verify it works

### Implementation for User Story 4

- [x] T030 [US4] Add call sign override support in src/tools/speak-status.ts (use provided or fall back to registered)
- [x] T031 [US4] Return skippedReason: "no_callsign" when neither registered nor provided
- [x] T032 [US4] Support MCP_VOICE_DEFAULT_CALLSIGN environment variable in src/index.ts

**Checkpoint**: Call sign protocol complete — flexible identification with proper error handling

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, packaging, and final validation

- [x] T033 [P] Create README.md with installation, VS Code config, usage examples (from quickstart.md)
- [x] T034 [P] Create LICENSE file (MIT)
- [x] T035 [P] Add bin entry to package.json for global CLI installation
- [x] T036 [P] Create .vscode/launch.json for debugging
- [x] T037 Run npm run build and verify dist/ output
- [ ] T038 Test end-to-end: npm link, configure in VS Code, verify speech works
- [ ] T039 Validate against quickstart.md scenarios

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (Setup)
    ↓
Phase 2 (Foundational) ←── BLOCKS all user stories
    ↓
┌───────────────────────────────────────────┐
│  User Stories can proceed in parallel:    │
│  Phase 3 (US1) ← MVP, do first            │
│  Phase 4 (US2) ← depends on US1 speak     │
│  Phase 5 (US3) ← depends on US1 speak     │
│  Phase 6 (US4) ← depends on US1           │
└───────────────────────────────────────────┘
    ↓
Phase 7 (Polish) ←── after all stories complete
```

### User Story Dependencies

| Story | Depends On | Can Parallel With |
|-------|------------|-------------------|
| US1 (P1) | Phase 2 only | — (MVP, do first) |
| US2 (P2) | Phase 2 + T018 (speak_status exists) | US3, US4 |
| US3 (P2) | Phase 2 + T018 (speak_status exists) | US2, US4 |
| US4 (P3) | Phase 2 + T017, T018 | US2, US3 |

### Within Each User Story

1. Unit tests written first (should fail initially)
2. Implementation until tests pass
3. Integration verification
4. Story checkpoint validation

### Parallel Opportunities per Phase

**Phase 1**: T003, T004, T005, T006, T007 can all run in parallel

**Phase 2**: T010, T011 can run in parallel after T009

**Phase 3**: T015, T016 can run in parallel (tests)

**Phase 4-6**: Once US1 implementation exists (T018), US2/US3/US4 can proceed in parallel

**Phase 7**: T033, T034, T035, T036 can all run in parallel

---

## Parallel Example: After Foundational Phase

```bash
# Thread 1: Complete MVP (User Story 1)
T015 → T016 → T017 → T018 → T019 → T020 → T021

# After T018 exists, Thread 2 can start:
T022 → T023 → T024 → T025

# Thread 3 (parallel with Thread 2):
T026 → T027 → T028 → T029

# Thread 4 (parallel with Thread 2 & 3):
T030 → T031 → T032
```

---

## Implementation Strategy

### MVP Scope (Recommended First Delivery)

Complete **Phase 1 + Phase 2 + Phase 3 (User Story 1)** for a working MVP:
- Server starts and connects via stdio
- Agent can register call sign
- Agent can speak status messages
- Messages are spoken with "[CallSign]: [phase]. [message]" format

**Estimated tasks for MVP**: T001–T021 (21 tasks)

### Incremental Delivery

1. **MVP**: US1 only — basic speaking works
2. **+Rate Limiting**: US2 — prevents spam
3. **+Deduplication**: US3 — filters duplicates  
4. **+Call Sign Flexibility**: US4 — override support
5. **+Polish**: Documentation and packaging

---

## Task Summary

| Phase | Tasks | Parallel Tasks |
|-------|-------|----------------|
| Setup | 8 | 5 |
| Foundational | 6 | 2 |
| US1 (MVP) | 7 | 2 |
| US2 (Rate Limit) | 4 | 1 |
| US3 (Dedup) | 4 | 1 |
| US4 (Call Sign) | 3 | 0 |
| Polish | 7 | 4 |
| **Total** | **39** | **15** |
