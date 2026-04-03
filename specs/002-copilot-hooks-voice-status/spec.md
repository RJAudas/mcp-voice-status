# Feature Specification: Copilot Agent Hooks Voice Status

**Feature Branch**: `002-copilot-hooks-voice-status`  
**Created**: April 3, 2026  
**Status**: Draft  
**Input**: User description: "Pivot from MCP server to GitHub Copilot agent hooks-based architecture for voice status updates via Windows TTS. Hooks fire automatically at agent lifecycle points — zero agent cooperation needed. Hook scripts receive structured JSON on stdin and invoke Windows TTS to speak brief summaries."

## Overview

A set of GitHub Copilot agent hook scripts that provide developers with audible spoken status updates about what their AI agent is doing, using Windows text-to-speech. Unlike the previous MCP server approach (which required the agent to explicitly call tools), hooks fire automatically at key agent lifecycle points — requiring zero agent cooperation. The developer can work hands-free, away from the screen, and still know what the agent is doing through brief spoken messages.

This completely replaces the MCP server architecture. The existing TTS engine logic (PowerShell System.Speech invocation, text sanitization, rate limiting, deduplication) is preserved and adapted into standalone PowerShell scripts that hook configurations invoke.

## Clarifications

### Session 2026-04-03

- Q: Should errors bypass rate limiting? → A: Errors always bypass rate limiting and are spoken immediately.
- Q: How should the speech state file handle concurrent access? → A: Last-write-wins with no locking; accept occasional duplicate speech on race. Performance is paramount — speech must never slow the agent.
- Q: Should the tool classification list be user-extensible? → A: JSON config file mapping tool names to interesting/noisy categories. Configuration infrastructure should be designed for future VS Code extension UI management.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Hear What the Agent Is Doing Without Watching (Priority: P1)

As a developer using GitHub Copilot (cloud agent or CLI), I want to hear brief spoken summaries of agent actions — tool completions, errors, session milestones — so I can stay informed about progress without watching the screen.

**Why this priority**: This is the core value proposition. Everything else (filtering, rate limiting) exists to make this experience pleasant.

**Independent Test**: Can be fully tested by configuring hooks, starting an agent session, and verifying that tool completions and session events produce audible speech output.

**Acceptance Scenarios**:

1. **Given** hooks are configured and an agent session starts, **When** the agent receives its initial prompt, **Then** the user hears a brief summary of the task (e.g., "Session started. Fixing auth bug")
2. **Given** hooks are configured and the agent edits a file, **When** the edit tool completes, **Then** the user hears a brief description (e.g., "Edited auth controller")
3. **Given** hooks are configured and a build command finishes, **When** the bash/powershell tool returns, **Then** the user hears a result summary (e.g., "Build succeeded" or "3 tests failed")
4. **Given** hooks are configured and the session ends, **When** the session stop event fires, **Then** the user hears the completion reason (e.g., "Session complete")

---

### User Story 2 - Only Hear Meaningful Updates, Not Noise (Priority: P1)

As a developer, I want the system to intelligently filter which tool completions are spoken so that I only hear about meaningful actions (edits, builds, test results) and not noisy read-only operations (file views, grep searches).

**Why this priority**: Without smart filtering, hooks would fire on every tool call, producing constant distracting audio. Filtering is essential for usability and is tightly coupled to the core experience.

**Independent Test**: Can be tested by triggering a mix of tool types (edit, view, grep, bash) and verifying that only the "interesting" tools produce audio.

**Acceptance Scenarios**:

1. **Given** the agent uses the "view" tool to read a file, **When** the postToolUse hook fires, **Then** no audio is produced
2. **Given** the agent uses the "grep" or "glob" tool, **When** the postToolUse hook fires, **Then** no audio is produced
3. **Given** the agent uses the "edit" tool to modify a file, **When** the postToolUse hook fires, **Then** the user hears a summary (e.g., "Edited utils.ts")
4. **Given** the agent runs a bash command, **When** the postToolUse hook fires, **Then** the user hears a result summary (e.g., "Command completed" or "Tests: 5 passed, 2 failed")

---

### User Story 3 - Prevent Audio Spam During Rapid Operations (Priority: P2)

As a developer, I want the system to rate-limit and deduplicate spoken messages so that rapid sequences of tool calls do not produce overwhelming audio.

**Why this priority**: Without rate limiting, agents that fire many tools in quick succession would create an unintelligible wall of sound. This is essential for pleasant usage but depends on the core hook infrastructure.

**Independent Test**: Can be tested by triggering rapid tool calls and verifying that messages are throttled appropriately.

**Acceptance Scenarios**:

1. **Given** a message was spoken within the last 3 seconds (default), **When** another hook fires, **Then** the new message is silently dropped
2. **Given** the identical message "Edited utils.ts" was spoken within the last 10 seconds (default), **When** the same message would be spoken again, **Then** it is silently deduplicated
3. **Given** the configurable rate limit interval has passed, **When** a new hook fires with a meaningful tool, **Then** the message is spoken normally
4. **Given** the user sets a custom rate limit interval via environment variable, **When** hooks fire, **Then** the custom interval is respected

---

### User Story 4 - Hear About Errors Immediately (Priority: P2)

As a developer, I want to hear about agent errors as soon as they occur so I can decide whether to intervene without needing to check the screen.

**Why this priority**: Errors are high-signal events that users should not miss. Error reporting is important but depends on the basic hook infrastructure.

**Independent Test**: Can be tested by triggering a tool that fails and verifying the error is spoken.

**Acceptance Scenarios**:

1. **Given** a tool call fails with an error, **When** the postToolUse hook fires with an error result, **Then** the user hears the error name and a brief description (e.g., "Error: network timeout")
2. **Given** the agent encounters an unrecoverable error, **When** the session ends with a failure reason, **Then** the user hears the failure reason spoken

---

### User Story 5 - Know When a New Task Begins (Priority: P3)

As a developer, I want to hear when I submit a new prompt to the agent so I have confirmation that my instruction was received and a summary of what was asked.

**Why this priority**: Useful for multi-turn conversations where the developer is away from the screen, but less critical than hearing tool results and errors.

**Independent Test**: Can be tested by submitting a prompt and verifying the hook speaks a summary.

**Acceptance Scenarios**:

1. **Given** the developer submits a new prompt to the agent, **When** the postChatTurn hook fires for the user message, **Then** the user hears a brief summary (e.g., "New task: add unit tests for login")

---

### User Story 6 - Configure Voice Behavior via Environment Variables (Priority: P3)

As a developer, I want to customize voice behavior (rate limit interval, dedup window, speech rate, volume) using environment variables so I can tune the experience to my preferences without editing scripts.

**Why this priority**: Important for personalization but the system works well with sensible defaults. Configuration is an enhancement.

**Independent Test**: Can be tested by setting environment variables and verifying changed behavior.

**Acceptance Scenarios**:

1. **Given** the environment variable for rate limit interval is set to 5 seconds, **When** hooks fire, **Then** the 5-second interval is used instead of the default 3 seconds
2. **Given** the environment variable for voice volume is set to 50, **When** a message is spoken, **Then** the speech is at 50% volume
3. **Given** no environment variables are set, **When** hooks fire, **Then** sensible defaults are used (3s rate limit, 10s dedup, normal rate, 100% volume)

---

### Edge Cases

- What happens when the Windows speech system is unavailable? The hook script exits silently without blocking the agent workflow.
- What happens when the JSON on stdin is malformed or empty? The script exits gracefully without speaking or crashing.
- What happens when a tool result contains malicious content (e.g., PowerShell injection attempts in file names or error messages)? Text is sanitized before being passed to TTS to prevent code execution.
- What happens when a message exceeds 200 characters? The message is truncated to 200 characters before speaking.
- What happens when the system audio is muted? The script still succeeds (the OS handles mute state; the hook does not check audio hardware).
- What happens when an unrecognized tool name appears? The script treats it as uninteresting by default and does not speak.
- What happens when the hook script itself fails? The agent workflow continues unaffected — hooks are non-blocking by design.
- What happens during concurrent hook invocations? Each invocation is an independent process; the state file uses last-write-wins with no locking. An occasional extra spoken message from a race condition is acceptable — correctness is not critical for a notification system.

## Requirements *(mandatory)*

### Functional Requirements

#### Hook Lifecycle Events

- **FR-001**: System MUST provide a hook that fires when an agent session starts, speaking a summary of the initial prompt
- **FR-002**: System MUST provide a hook that fires after a user submits a new prompt, speaking a brief summary of the instruction
- **FR-003**: System MUST provide a hook that fires after each tool use, selectively speaking a summary based on tool type and result
- **FR-004**: System MUST provide a hook that fires when the agent session ends, speaking the completion or abort reason
- **FR-005**: System MUST provide a hook that fires on agent errors, speaking the error name and a short description

#### Smart Filtering

- **FR-006**: System MUST classify tools as "interesting" (edit, create, bash, powershell, and similar write/execute tools) or "noisy" (view, grep, glob, read, and similar read-only tools). Tool classification MUST be defined in a JSON configuration file that users can edit directly or that a future VS Code extension UI can manage.
- **FR-007**: System MUST only speak for interesting tool completions and silently skip noisy tools
- **FR-008**: System MUST treat unrecognized tool names as noisy by default

#### Rate Limiting and Deduplication

- **FR-009**: System MUST enforce a minimum time interval between spoken messages (configurable, default 3 seconds). Error messages are exempt from rate limiting and MUST always be spoken immediately.
- **FR-010**: System MUST not repeat identical messages within a configurable time window (default 10 seconds)
- **FR-011**: Rate limiting and deduplication state MUST persist across hook invocations within a session via a filesystem-based state file using last-write-wins semantics (no file locking). Occasional duplicate speech due to race conditions is acceptable.

#### Text-to-Speech

- **FR-012**: System MUST use Windows native text-to-speech (System.Speech.Synthesis) with no external dependencies
- **FR-013**: System MUST operate entirely locally with zero network calls
- **FR-014**: System MUST sanitize all text before passing it to TTS to prevent injection attacks
- **FR-015**: System MUST limit all spoken messages to under 200 characters
- **FR-016**: System MUST not block the agent workflow — hook scripts MUST launch speech asynchronously (fire-and-forget) so the hook process exits immediately without waiting for TTS playback to complete

#### Message Summarization

- **FR-017**: System MUST summarize tool results intelligently rather than reading raw output (e.g., "Build succeeded" instead of the full build log, "3 tests failed" instead of the full test output)
- **FR-018**: System MUST extract the file name from edit/create tool results for spoken context (e.g., "Edited auth-controller.ts")
- **FR-019**: System MUST detect common patterns in command output (test results, build status, lint results) and summarize them

#### Configuration

- **FR-020**: System MUST support a JSON configuration file as the primary configuration mechanism for all settings (tool classification, rate limit interval, dedup window, TTS timeout, voice rate, volume). The JSON structure MUST be designed for future VS Code extension UI management (machine-readable, well-documented schema). Environment variables MAY override JSON config values for quick per-session tuning.
- **FR-021**: System MUST use sensible defaults when neither JSON config nor environment variables are set
- **FR-022**: Hook configuration MUST live in `.github/hooks/` as JSON files, with PowerShell scripts in a sibling `scripts/` directory. Voice status settings (tool classification, rate limits, voice preferences) MUST live in a separate JSON config file within the same directory structure.

#### Compatibility

- **FR-023**: System MUST work with GitHub Copilot cloud agent (coding agent)
- **FR-024**: System MUST work with GitHub Copilot CLI
- **FR-025**: System MUST require Windows with PowerShell 5.1 or later and the built-in System.Speech assembly

### Key Entities

- **Hook Configuration**: A JSON file that maps an agent lifecycle event to a PowerShell script. Contains the event name, the script path, and optional metadata.
- **Voice Status Configuration**: A JSON config file containing tool classification mappings, rate limit/dedup settings, and voice preferences. Structured for machine readability to support future VS Code extension UI management.
- **Hook Event Payload**: The structured JSON that the agent sends on stdin when a hook fires. Contains event type, tool name, tool arguments, tool result, prompt text, error details, etc.
- **Speech State**: A lightweight persistent record (file-based) tracking the last spoken timestamp and recent message hashes, used for rate limiting and deduplication across independent hook invocations.
- **Tool Classification**: A categorization of agent tools into "interesting" (worth speaking about) and "noisy" (silently skipped) groups, used by the post-tool-use hook to decide whether to speak.
- **Speech Message**: The final sanitized, summarized, truncated text that is spoken aloud. Under 200 characters, derived from the hook event payload.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users hear a spoken status update within 2 seconds of a qualifying agent event (interesting tool completion, session start/stop, error)
- **SC-002**: Zero spoken messages are produced for read-only tool operations (view, grep, glob, read) in normal usage
- **SC-003**: No more than one message is spoken per configured interval (default 3 seconds) regardless of how many hooks fire
- **SC-004**: Identical messages within the dedup window (default 10 seconds) result in only one spoken output
- **SC-005**: 100% of spoken text is under 200 characters
- **SC-006**: Zero network connections are made during normal operation
- **SC-007**: Hook scripts do not block or slow agent workflow — hook execution is non-blocking
- **SC-008**: All user-controlled text (prompts, tool arguments, error messages) is sanitized before TTS to prevent code execution
- **SC-009**: System works out-of-the-box on Windows 10/11 with no additional software installation required
- **SC-010**: All configuration can be managed via a JSON config file (designed for future VS Code extension UI) and optionally overridden via environment variables

## Assumptions

- Windows 10 or later is the target operating system
- PowerShell 5.1 or later is available (included with Windows 10+)
- The System.Speech assembly is available (built into .NET Framework on Windows)
- Users have audio output configured and working
- GitHub Copilot agent hooks follow the documented hooks protocol: hook scripts receive JSON on stdin and are invoked at defined lifecycle points
- Hooks are non-blocking — the agent does not wait for hook scripts to finish before continuing
- Each hook invocation runs as an independent process (no shared in-memory state between invocations)
- The `.github/hooks/` directory is the standard location for hook configuration
- Rate limiting and deduplication can be coordinated via a temporary file in the system temp directory
- The hook JSON payload includes tool name, tool arguments, tool result, prompt text, and error details as applicable per event type
- "Agent" is an acceptable spoken prefix when identifying the AI assistant
- Default rate limit of 3 seconds and dedup window of 10 seconds provide a good balance for most users
