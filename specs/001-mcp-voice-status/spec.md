# Feature Specification: MCP Voice Status Server

**Feature Branch**: `001-mcp-voice-status`  
**Created**: January 18, 2026  
**Status**: Draft  
**Input**: User description: "MCP server that provides a tool for VS Code agents to emit short spoken status messages locally on Windows. Requirements: local-only; stdio MCP server; one primary tool for speaking confirm/waiting/update/done/error; every spoken message is 1-2 sentences and always starts with an agent call sign; include rate limiting and deduping so it doesn't spam audio."

## Overview

A local-only MCP (Model Context Protocol) server that enables VS Code agents to provide audible status feedback to users via Windows text-to-speech. The server exposes a single tool that speaks short status messages, helping users stay aware of agent activity without constantly watching the screen.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Receive Audible Status During Long Operations (Priority: P1)

As a developer using VS Code with an AI agent, I want to hear brief spoken status updates so that I can work on other tasks or look away from the screen while staying informed about agent progress.

**Why this priority**: This is the core value proposition—enabling hands-free awareness of agent activity.

**Independent Test**: Can be fully tested by triggering a speak command and verifying audio output with the correct call sign prefix.

**Acceptance Scenarios**:

1. **Given** the MCP server is running and connected, **When** an agent calls the speak tool with status type "confirm" and message "Starting code review", **Then** the user hears "[CallSign], confirm. Starting code review." spoken aloud
2. **Given** the MCP server is running, **When** an agent calls the speak tool with status type "done" and message "Build completed successfully", **Then** the user hears "[CallSign], done. Build completed successfully." spoken aloud
3. **Given** the MCP server is running, **When** an agent calls the speak tool with status type "error" and message "Failed to connect to database", **Then** the user hears "[CallSign], error. Failed to connect to database." spoken aloud

---

### User Story 2 - Prevent Audio Spam with Rate Limiting (Priority: P2)

As a user, I want the system to limit how frequently messages are spoken so that I'm not overwhelmed by constant audio during rapid agent operations.

**Why this priority**: Without rate limiting, the tool could become annoying and unusable during high-activity periods.

**Independent Test**: Can be tested by rapidly calling the speak tool multiple times and verifying that excess calls are silently dropped or queued appropriately.

**Acceptance Scenarios**:

1. **Given** a message was spoken within the last 2 seconds, **When** another speak request arrives, **Then** the new request is queued or dropped according to configured limits
2. **Given** the rate limit threshold has been exceeded, **When** additional speak requests arrive, **Then** the system returns a success response but does not produce audio output
3. **Given** the rate limit window has passed, **When** a new speak request arrives, **Then** the message is spoken normally

---

### User Story 3 - Avoid Duplicate Messages with Deduplication (Priority: P2)

As a user, I want identical consecutive messages to be deduplicated so that I don't hear the same status repeated multiple times in quick succession.

**Why this priority**: Agents may inadvertently send duplicate messages, and hearing repetition degrades the user experience.

**Independent Test**: Can be tested by sending the same message twice rapidly and verifying only one audio output occurs.

**Acceptance Scenarios**:

1. **Given** a message "Processing files" was spoken within the dedup window, **When** the same message "Processing files" is requested again, **Then** the duplicate is silently ignored
2. **Given** a message "Processing files" was spoken, **When** a different message "Files processed" is requested, **Then** the new message is spoken normally
3. **Given** the dedup window has expired, **When** the same message is requested again, **Then** the message is spoken (no longer considered a duplicate)

---

### User Story 4 - Identify Agent by Call Sign (Priority: P3)

As a user working with multiple agents or wanting clear audio identification, I want each spoken message to begin with a configurable call sign so that I know which agent is speaking.

**Why this priority**: Call signs provide clear identification and make messages feel intentional rather than random system sounds.

**Independent Test**: Can be tested by configuring different call signs and verifying they prefix all spoken messages.

**Acceptance Scenarios**:

1. **Given** a call sign is configured as "Copilot", **When** any speak request is processed, **Then** the spoken output begins with "Copilot,"
2. **Given** a call sign is provided in the tool call, **When** the speak request is processed, **Then** the provided call sign overrides any default
3. **Given** no call sign is configured or provided, **When** a speak request is processed, **Then** a sensible default call sign is used (e.g., "Agent")

---

### Edge Cases

- What happens when the Windows speech system is unavailable or fails? The tool returns an error status without crashing.
- What happens when the message exceeds the 2-sentence limit? The message is truncated or rejected with a clear error.
- What happens when an invalid status type is provided? The tool returns a validation error.
- What happens when the call sign contains special characters or is extremely long? Reasonable validation is applied.
- What happens during system audio mute? The tool still succeeds (OS handles mute state).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST communicate via stdio (standard input/output) transport as per MCP specification
- **FR-002**: System MUST expose a single primary tool for speaking status messages
- **FR-003**: System MUST support five status types: "confirm", "waiting", "update", "done", and "error"
- **FR-004**: System MUST prefix every spoken message with the configured or provided call sign
- **FR-005**: System MUST limit spoken messages to 1-2 sentences maximum
- **FR-006**: System MUST implement rate limiting to prevent audio spam (configurable, default: minimum 2 seconds between messages)
- **FR-007**: System MUST implement message deduplication within a configurable time window (default: 10 seconds)
- **FR-008**: System MUST operate entirely locally with no network calls or external service dependencies
- **FR-009**: System MUST use Windows native text-to-speech capabilities
- **FR-010**: System MUST return appropriate success/error responses for all tool calls
- **FR-011**: System MUST handle speech synthesis failures gracefully without crashing
- **FR-012**: System MUST validate that messages do not exceed length limits before attempting to speak
- **FR-013**: System MUST allow call sign to be configured at server startup or overridden per-call

### Key Entities

- **StatusMessage**: Represents a request to speak a status update
  - Status type (enum: confirm, waiting, update, done, error)
  - Message content (string, 1-2 sentences)
  - Optional call sign override
  
- **RateLimiter**: Tracks message timing to enforce rate limits
  - Timestamp of last spoken message
  - Configurable minimum interval
  
- **Deduplicator**: Tracks recent messages to prevent duplicates
  - Recent message cache with timestamps
  - Configurable dedup window duration

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users hear status messages within 500ms of the speak tool being called (excluding rate-limited/deduped calls)
- **SC-002**: Rate limiting prevents more than one message per configured interval (default 2 seconds)
- **SC-003**: Identical messages within the dedup window (default 10 seconds) result in only one audio output
- **SC-004**: 100% of spoken messages begin with the configured call sign followed by the status type
- **SC-005**: Server starts and becomes ready to accept tool calls within 3 seconds
- **SC-006**: All tool calls receive a response within 1 second (not counting speech duration)
- **SC-007**: Server operates with zero network connections during normal operation

## Assumptions

- Windows 10 or later is the target operating system
- The Windows Speech API (SAPI) or equivalent is available and functional
- Users have audio output configured and working on their system
- The MCP client (VS Code agent) handles connection management and reconnection
- Default rate limit of 2 seconds between messages is appropriate for most use cases
- Default dedup window of 10 seconds balances responsiveness with duplicate prevention
- "Agent" is an acceptable default call sign when none is configured
