<!--
  SYNC IMPACT REPORT
  ==================
  Version change: (prior draft) → 1.0.0 (initial ratification)

  This constitution replaces a preliminary draft (2026-01-18) with the
  project owner's authoritative 8-principle framework.

  Modified principles (prior draft → this version):
    - "Windows-First, Local-Only" → split into
      "Local-Only and Private" (III) and "Windows-Native" (VI)
    - "Security-First Design" → refined as "Security by Default" (V)
    - "Minimal Dependencies" → absorbed into
      "Zero-Friction Adoption" (I) and "Windows-Native" (VI)
    - "Simplicity & YAGNI" → refined as "Keep It Small" (VIII)

  Removed from prior draft (demoted to implementation details):
    - "Agent Call Sign Protocol" (implementation detail, not principle)
    - "Structured Status Phases" (implementation detail, not principle)
    - "Rate Limiting" (absorbed into Audio-First UX, Principle IV)
    - "Security Requirements" standalone section (merged into Principle V)
    - "Development Standards" standalone section (distributed across
      Principles VI, VII, and VIII)

  Added principles:
    - I.   Zero-Friction Adoption (new)
    - II.  Agent-Invisible (new)
    - IV.  Audio-First UX (new, absorbs rate-limiting/dedup concerns)
    - VII. Tested and Reliable (new)

  Added sections:
    - Core Principles (I–VIII, 8 principles)
    - Governance (amendment procedure, versioning policy, compliance)

  Templates requiring updates:
    ✅ plan-template.md — Constitution Check section is generic; compatible
    ✅ spec-template.md — Requirements section is generic; compatible
    ✅ tasks-template.md — Phase structure is generic; compatible
    ✅ No command templates exist; nothing to update

  Follow-up TODOs: None
-->

# MCP Voice Status Constitution

Audible spoken status updates for AI coding agents on Windows.
Developers hear what their agent is doing and keep working hands-free.

## Core Principles

### I. Zero-Friction Adoption

The tool MUST be drop-in simple with no setup ceremony.

- Copying the project files into a repository and pointing an MCP
  config at the entry script MUST be sufficient to start using it.
- No installers, system-wide registrations, or manual PATH edits
  are permitted.
- Sensible defaults MUST ship for every configurable value so that
  zero-configuration usage produces useful behavior.
- Optional configuration MUST be limited to a single JSON file
  with documented keys and safe fallback values.
- Runtime dependencies MUST NOT exceed what Windows and the agent
  runtime (Node.js LTS, MCP SDK) already provide.

**Rationale**: Developer tools that require complex setup do not get
adopted. Every friction point is a reason to uninstall.

### II. Agent-Invisible

The system MUST operate without agent cooperation or awareness.

- Agents MUST NOT be required to include custom instructions,
  special prompts, or awareness of the narration system.
- The tool MUST hook into the agent lifecycle (MCP tool calls,
  status events) automatically via protocol-level mechanisms.
- If an agent explicitly invokes a voice tool, the system MUST
  still function correctly, but explicit invocation MUST NOT
  be a prerequisite for basic operation.
- No modification to the agent's system prompt, persona, or
  behavior is permitted as a hard requirement.

**Rationale**: Requiring agent cooperation couples the tool to
specific agent versions and prompt formats. Automatic operation
makes the tool universally compatible and future-proof.

### III. Local-Only and Private

All processing MUST execute entirely on the developer's machine.

- No network calls of any kind: no HTTP requests, no WebSocket
  connections, no DNS lookups, no telemetry pings.
- No cloud services, external APIs, or remote logging endpoints.
- All data — prompts, tool arguments, error messages, TTS text —
  MUST remain on-device and MUST NOT be persisted beyond the
  current session unless the developer explicitly enables logging.
- The tool MUST function identically with no internet connectivity.

**Rationale**: Developers working with proprietary code and AI
agents require absolute confidence that their workflow data never
leaves their machine.

### IV. Audio-First UX

Spoken messages MUST be brief, clear, and never annoying.

- Messages MUST be 1–2 short sentences maximum. Verbose
  explanations MUST be rejected or truncated before speaking.
- Rate limiting MUST be a first-class feature with a sensible
  default (minimum 3-second interval per source). The minimum
  configurable interval MUST NOT go below 1 second.
- Deduplication MUST be a first-class feature: identical messages
  within a configurable window MUST be silently dropped.
- When the system must choose between speaking and staying silent,
  silence MUST be the default. Audio spam is a product failure.
- Coalescing or dropping of queued messages during rate-limit
  windows MUST be supported and configurable.

**Rationale**: An audio interface that talks too much or too often
trains the developer to mute it, defeating its purpose entirely.

### V. Security by Default

All input from agent context is untrusted. Defense is mandatory.

- Every string originating from agent context (prompts, tool
  arguments, error messages) MUST be sanitized before being
  passed to PowerShell or any TTS API.
- Shell metacharacters, SSML/XML tags, and escape sequences
  MUST be stripped or escaped. Command injection via crafted
  TTS text MUST be provably impossible.
- All MCP tool inputs MUST be validated against strict schemas
  before any processing occurs.
- TTS content MUST be treated as plain text only. No script
  evaluation, no dynamic code generation from agent input.
- On any validation failure, the system MUST refuse the request
  and return a structured error. Fail-safe defaults apply.
- The server MUST NOT execute any operation requiring elevated
  (administrator) privileges.
- The server MUST NOT store API keys, tokens, or credentials.

**Rationale**: An MCP server that receives arbitrary agent-
generated strings is an injection attack surface. Every input
path must be hardened by default, not by configuration.

### VI. Windows-Native

PowerShell 5.1 and System.Speech are the only TTS runtime
dependencies.

- TTS MUST use `System.Speech.Synthesis.SpeechSynthesizer` via
  PowerShell 5.1, which ships with Windows 10 and later.
- No Python, no external Node.js TTS libraries, no compiled
  native addons (node-gyp), and no third-party TTS engines
  are permitted in the shipped product.
- TTS execution MUST spawn a separate PowerShell process. No
  `eval`, `Invoke-Expression` on unsanitized input, or
  in-process script execution is permitted.
- PowerShell TTS calls MUST enforce a timeout (default 30
  seconds). Hung processes MUST be killed automatically.
- Dev-only dependencies (testing, linting) are permitted but
  MUST NOT affect the runtime artifact.

**Rationale**: Relying exclusively on built-in Windows
capabilities eliminates supply-chain risk, avoids native
compilation headaches, and guarantees the tool works on any
standard Windows 10/11 developer machine.

### VII. Tested and Reliable

Every component that processes input or manages state MUST have
automated tests.

- Unit tests MUST cover all input validation, sanitization,
  and rate-limiting logic.
- Integration tests MUST verify TTS invocation paths (mocking
  PowerShell is acceptable in CI environments).
- Security-sensitive code paths MUST have explicit test
  coverage demonstrating that injection attempts are blocked.
- The MCP hook layer MUST be tested to confirm it never throws
  unhandled exceptions into the agent runtime.
- Hooks and middleware MUST fail silently with structured
  logging rather than crashing or blocking agent execution.
  A broken voice notification MUST NOT break the developer's
  coding workflow.
- Minimum coverage target: 80% of `src/` (excluding type
  definitions).

**Rationale**: A tool that sits in the critical path of an AI
agent's execution loop must be demonstrably reliable. Silent
failure with logging is always preferable to a crash that halts
the developer's work.

### VIII. Keep It Small

This is a focused tool, not a framework. Scope creep is a defect.

- The entire shipped deliverable SHOULD consist of a handful of
  scripts, one entry point, and one JSON configuration file.
- Every proposed feature MUST have a documented use case before
  implementation begins.
- Prefer configuration over code when behavior needs to vary.
- Avoid premature abstraction; refactor only when clear patterns
  have emerged across at least two concrete use cases.
- No feature may be added that violates any other principle in
  this constitution.

**Rationale**: A small, focused tool is easier to audit, easier
to maintain, and harder to break than a sprawling framework. If
it does one thing well, developers will keep it installed.

## Governance

This Constitution is the authoritative source for project
constraints, design decisions, and non-negotiable rules.

### Compliance

- All code changes MUST comply with these principles.
- Pull requests touching core functionality MUST reference the
  relevant principle(s) by number (e.g., "per Principle V").
- Temporary violations MUST be documented and justified in the
  PR description with a remediation timeline.

### Amendment Procedure

Amendments to this Constitution require:

1. A written proposal with rationale explaining the change.
2. Review of downstream impacts on templates, specs, and tasks.
3. A version increment following the versioning policy below.
4. Update of the `Last Amended` date to the amendment date.

### Versioning Policy

- **MAJOR**: Principle removal, redefinition, or backward-
  incompatible governance change.
- **MINOR**: New principle added, existing section materially
  expanded, or significant guidance change.
- **PATCH**: Typo fixes, clarifications, non-semantic wording
  improvements.

### Compliance Review Expectations

- Automated linting and test gates MUST pass before merge.
- Security-sensitive changes MUST receive explicit review against
  Principle V before approval.
- Architectural changes MUST be evaluated against Principles I,
  II, VI, and VIII before approval.

**Version**: 1.0.0 | **Ratified**: 2026-04-02 | **Last Amended**: 2026-04-02
