# Data Model: MCP Voice Status Server

**Phase**: 1 - Design  
**Date**: 2026-01-18  
**Feature**: [spec.md](spec.md)

## Overview

This document defines the TypeScript interfaces and types for the MCP Voice Status Server. The server is stateless beyond in-memory runtime state; no persistence layer is required.

---

## Core Types

### StatusPhase

Enumeration of valid status phases per Constitution III.

```typescript
/**
 * Valid status phases for spoken messages.
 * Maps to Constitution III structured status phases.
 */
export type StatusPhase = 'confirm' | 'waiting' | 'blocked' | 'done' | 'error';

export const STATUS_PHASES: readonly StatusPhase[] = [
  'confirm',
  'waiting',
  'blocked',
  'done',
  'error'
] as const;
```

### CallSign

Call sign constraints per Constitution II.

```typescript
/**
 * Call sign validation rules:
 * - Alphanumeric with optional hyphens
 * - 1-20 characters
 * - No leading/trailing hyphens
 */
export interface CallSignConfig {
  /** The call sign string (e.g., "Copilot", "Agent-7") */
  value: string;
  /** Timestamp when registered */
  registeredAt: number;
}

// Validation constants
export const CALLSIGN_MIN_LENGTH = 1;
export const CALLSIGN_MAX_LENGTH = 20;
export const CALLSIGN_PATTERN = /^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$/;
```

---

## Request/Response Types

### SpeakStatusRequest

Input for the `speak_status` tool.

```typescript
/**
 * Request to speak a status message.
 */
export interface SpeakStatusRequest {
  /** Status phase category */
  phase: StatusPhase;
  
  /** 
   * Message content (1-2 sentences).
   * Will be prefixed with call sign and phase.
   */
  message: string;
  
  /**
   * Optional call sign override.
   * If not provided, uses the registered call sign.
   */
  callSign?: string;
}

// Validation constants
export const MESSAGE_MIN_LENGTH = 1;
export const MESSAGE_MAX_LENGTH = 200;
```

### SpeakStatusResponse

Output from the `speak_status` tool.

```typescript
/**
 * Response from speak_status tool.
 */
export interface SpeakStatusResponse {
  /** Whether the message was spoken */
  spoken: boolean;
  
  /** 
   * If not spoken, the reason why:
   * - 'rate_limited': Exceeded rate limit
   * - 'deduplicated': Duplicate message filtered
   * - 'no_callsign': No call sign registered
   */
  skippedReason?: 'rate_limited' | 'deduplicated' | 'no_callsign';
  
  /** Cooldown remaining in ms (if rate limited) */
  cooldownMs?: number;
  
  /** The full text that was spoken (for debugging) */
  spokenText?: string;
}
```

### RegisterCallSignRequest

Input for the `register_callsign` tool.

```typescript
/**
 * Request to register an agent call sign.
 */
export interface RegisterCallSignRequest {
  /** 
   * The call sign to register.
   * Must match CALLSIGN_PATTERN.
   */
  callSign: string;
}
```

### RegisterCallSignResponse

Output from the `register_callsign` tool.

```typescript
/**
 * Response from register_callsign tool.
 */
export interface RegisterCallSignResponse {
  /** Whether registration succeeded */
  success: boolean;
  
  /** The registered call sign */
  callSign: string;
  
  /** Previous call sign if one was replaced */
  previousCallSign?: string;
}
```

---

## Internal State Types

### RateLimiterState

State for per-callsign rate limiting.

```typescript
/**
 * Rate limiter entry for a single call sign.
 */
export interface RateLimitEntry {
  /** Timestamp of last spoken message */
  lastSpokenAt: number;
}

/**
 * Rate limiter configuration.
 */
export interface RateLimiterConfig {
  /** Minimum interval between messages in milliseconds */
  minIntervalMs: number;
}

// Default configuration per Constitution IV
export const DEFAULT_RATE_LIMIT_MS = 3000;  // 3 seconds
export const MIN_RATE_LIMIT_MS = 1000;      // 1 second minimum
```

### DeduplicatorState

State for message deduplication.

```typescript
/**
 * Deduplication cache entry for a single call sign.
 */
export interface DedupeEntry {
  /** Hash of the last message (phase + content) */
  messageHash: string;
  
  /** Timestamp when the message was spoken */
  spokenAt: number;
}

/**
 * Deduplicator configuration.
 */
export interface DeduplicatorConfig {
  /** Time window for deduplication in milliseconds */
  windowMs: number;
}

// Default configuration
export const DEFAULT_DEDUP_WINDOW_MS = 10000;  // 10 seconds
```

### SpeechQueueItem

Item in the speech queue.

```typescript
/**
 * Queued speech item.
 */
export interface SpeechQueueItem {
  /** Full text to speak (including call sign prefix) */
  text: string;
  
  /** Call sign of the requesting agent */
  callSign: string;
  
  /** Status phase */
  phase: StatusPhase;
  
  /** Timestamp when queued */
  queuedAt: number;
  
  /** Promise resolution callback */
  resolve: () => void;
  
  /** Promise rejection callback */
  reject: (error: Error) => void;
}
```

---

## Server State

### ServerState

Aggregate runtime state for the MCP server.

```typescript
/**
 * Runtime state for the MCP Voice Status server.
 * All state is in-memory; nothing is persisted.
 */
export interface ServerState {
  /** Currently registered call sign (single agent) */
  callSign: CallSignConfig | null;
  
  /** Rate limit entries by call sign */
  rateLimits: Map<string, RateLimitEntry>;
  
  /** Deduplication entries by call sign */
  dedupeCache: Map<string, DedupeEntry>;
  
  /** Whether the speech queue is currently processing */
  speechQueueActive: boolean;
}

/**
 * Initial server state.
 */
export function createInitialState(): ServerState {
  return {
    callSign: null,
    rateLimits: new Map(),
    dedupeCache: new Map(),
    speechQueueActive: false
  };
}
```

---

## Configuration Types

### ServerConfig

Server-level configuration (set at startup).

```typescript
/**
 * Server configuration options.
 */
export interface ServerConfig {
  /** Server name for MCP protocol */
  name: string;
  
  /** Server version */
  version: string;
  
  /** Default call sign (optional) */
  defaultCallSign?: string;
  
  /** Rate limiting configuration */
  rateLimit: RateLimiterConfig;
  
  /** Deduplication configuration */
  dedup: DeduplicatorConfig;
  
  /** TTS configuration */
  tts: TTSConfig;
}

/**
 * TTS-specific configuration.
 */
export interface TTSConfig {
  /** Timeout for PowerShell TTS process in ms */
  timeoutMs: number;
  
  /** Speech rate (-10 to 10, 0 is normal) */
  rate: number;
  
  /** Volume (0 to 100) */
  volume: number;
}

// Default configuration
export const DEFAULT_CONFIG: ServerConfig = {
  name: 'mcp-voice-status',
  version: '1.0.0',
  defaultCallSign: undefined,
  rateLimit: {
    minIntervalMs: DEFAULT_RATE_LIMIT_MS
  },
  dedup: {
    windowMs: DEFAULT_DEDUP_WINDOW_MS
  },
  tts: {
    timeoutMs: 30000,
    rate: 0,
    volume: 100
  }
};
```

---

## Error Types

### VoiceStatusError

Custom error type for server errors.

```typescript
/**
 * Error codes for voice status operations.
 */
export type VoiceStatusErrorCode =
  | 'INVALID_CALLSIGN'
  | 'INVALID_PHASE'
  | 'INVALID_MESSAGE'
  | 'NO_CALLSIGN'
  | 'TTS_FAILED'
  | 'TTS_TIMEOUT'
  | 'SANITIZATION_FAILED';

/**
 * Custom error class for voice status operations.
 */
export class VoiceStatusError extends Error {
  constructor(
    public readonly code: VoiceStatusErrorCode,
    message: string,
    public readonly details?: Record<string, unknown>
  ) {
    super(message);
    this.name = 'VoiceStatusError';
  }
}
```

---

## Type Summary

| Type | Purpose | Persisted |
|------|---------|-----------|
| `StatusPhase` | Enum of valid status phases | No |
| `CallSignConfig` | Registered call sign state | No (in-memory) |
| `SpeakStatusRequest` | Input for speak_status tool | No |
| `SpeakStatusResponse` | Output from speak_status tool | No |
| `RegisterCallSignRequest` | Input for register_callsign tool | No |
| `RegisterCallSignResponse` | Output from register_callsign tool | No |
| `RateLimitEntry` | Per-callsign rate limit state | No (in-memory) |
| `DedupeEntry` | Per-callsign dedup cache entry | No (in-memory) |
| `SpeechQueueItem` | Item in speech queue | No (in-memory) |
| `ServerState` | Aggregate runtime state | No (in-memory) |
| `ServerConfig` | Server configuration | No (startup config) |
