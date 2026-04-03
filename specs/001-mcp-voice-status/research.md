# Research: MCP Voice Status Server

**Phase**: 0 - Research  
**Date**: 2026-01-18  
**Feature**: [spec.md](spec.md)

## Research Tasks

This document consolidates findings for all technical unknowns and best practices needed before implementation.

---

## 1. MCP TypeScript SDK Patterns

**Task**: Research `@modelcontextprotocol/sdk` for stdio MCP server implementation.

### Decision: Use `McpServer` with `StdioServerTransport`

**Implementation Pattern**:

```typescript
import { McpServer, StdioServerTransport } from '@modelcontextprotocol/server';
import * as z from 'zod';

const server = new McpServer({
  name: 'mcp-voice-status',
  version: '1.0.0'
});

// Register tool with Zod schema validation
server.registerTool(
  'speak_status',
  {
    description: 'Speak a status message',
    inputSchema: {
      phase: z.enum(['confirm', 'waiting', 'blocked', 'done', 'error']),
      message: z.string().max(200)
    }
  },
  async ({ phase, message }) => ({
    content: [{ type: 'text', text: 'Spoken successfully' }]
  })
);

// Connect to stdio
const transport = new StdioServerTransport();
await server.connect(transport);
```

**Rationale**: 
- `McpServer` is the high-level API; handles protocol negotiation automatically
- `registerTool()` is the current API (not deprecated `tool()`)
- Zod schemas provide runtime validation and TypeScript types
- `StdioServerTransport` handles stdin/stdout MCP protocol framing

**Alternatives Considered**:
- Low-level `Server` class: More control but unnecessary complexity
- WebSocket transport: Not needed for local-only stdio use case

### Key Best Practices

1. **Use `console.error()` for all logging** - stdout is reserved for MCP protocol
2. **Handle SIGINT/SIGTERM** - Clean shutdown for stdio processes
3. **Tool errors use `isError: true`** - Signals error to LLM for self-correction
4. **Zod for all input schemas** - Automatic validation + type inference

---

## 2. Windows TTS via PowerShell

**Task**: Research Windows `System.Speech.Synthesis` invocation from Node.js.

### Decision: Spawn PowerShell with `execFile` and argument array

**Implementation Pattern**:

```typescript
import { execFile } from 'child_process';
import { promisify } from 'util';

const execFileAsync = promisify(execFile);

async function speak(text: string, timeout = 30000): Promise<void> {
  const sanitized = sanitizeText(text);
  
  const psScript = `
    Add-Type -AssemblyName System.Speech
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $synth.SetOutputToDefaultAudioDevice()
    $synth.Speak('${sanitized}')
    $synth.Dispose()
  `.trim();

  await execFileAsync('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy', 'Bypass',
    '-Command', psScript
  ], {
    timeout,
    windowsHide: true
  });
}
```

**Rationale**:
- `execFile` with args array avoids shell injection (vs `exec` with string)
- `-NoProfile -NonInteractive` = faster startup, no prompts
- `windowsHide: true` prevents console flash
- Built-in `timeout` option handles hung processes

**Alternatives Considered**:
- `edge-js` / native addon: Violates Constitution VI (no native addons)
- `say.js` package: Adds unnecessary dependency; we control the code
- `child_process.exec`: Shell injection risk

### Text Sanitization Requirements

```typescript
function sanitizeText(text: string): string {
  let result = text;
  result = result.replace(/\0/g, '');           // Remove null bytes
  result = result.replace(/<[^>]*>/g, '');      // Remove SSML/XML tags
  result = result.replace(/'/g, "''");          // Escape single quotes for PS
  result = result.replace(/`/g, '');            // Remove PS escape char
  result = result.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, ''); // Control chars
  result = result.replace(/\s+/g, ' ').trim();  // Normalize whitespace
  if (result.length > 500) result = result.substring(0, 500);
  return result;
}
```

---

## 3. Rate Limiting Approach

**Task**: Research per-callsign rate limiting for audio messages.

### Decision: Token bucket algorithm (simplified)

**Implementation Pattern**:

```typescript
interface RateLimitEntry {
  lastSpoken: number;  // timestamp
}

class RateLimiter {
  private entries = new Map<string, RateLimitEntry>();
  private minIntervalMs: number;

  constructor(minIntervalSeconds = 3) {
    this.minIntervalMs = minIntervalSeconds * 1000;
  }

  canSpeak(callSign: string): boolean {
    const now = Date.now();
    const entry = this.entries.get(callSign);
    
    if (!entry || (now - entry.lastSpoken) >= this.minIntervalMs) {
      return true;
    }
    return false;
  }

  recordSpoken(callSign: string): void {
    this.entries.set(callSign, { lastSpoken: Date.now() });
  }

  getRemainingCooldown(callSign: string): number {
    const entry = this.entries.get(callSign);
    if (!entry) return 0;
    const elapsed = Date.now() - entry.lastSpoken;
    return Math.max(0, this.minIntervalMs - elapsed);
  }
}
```

**Rationale**:
- Simple sliding window per callsign (not global)
- Constitution IV specifies per-callsign rate limiting
- Minimum 1 second enforced; default 3 seconds
- No complex token bucket needed for single-message-per-interval

**Alternatives Considered**:
- Global rate limit: Violates Constitution IV (per callsign)
- Token bucket with burst: Unnecessary complexity for audio use case
- Leaky bucket: Overkill for simple interval enforcement

---

## 4. Message Deduplication

**Task**: Research deduplication strategy for repeated messages.

### Decision: Hash-based cache with TTL

**Implementation Pattern**:

```typescript
import { createHash } from 'crypto';

interface DedupeEntry {
  hash: string;
  timestamp: number;
}

class Deduplicator {
  private cache = new Map<string, DedupeEntry>();  // keyed by callSign
  private windowMs: number;

  constructor(windowSeconds = 10) {
    this.windowMs = windowSeconds * 1000;
  }

  isDuplicate(callSign: string, phase: string, message: string): boolean {
    const hash = this.hashMessage(phase, message);
    const now = Date.now();
    const entry = this.cache.get(callSign);

    if (entry && entry.hash === hash && (now - entry.timestamp) < this.windowMs) {
      return true;
    }
    return false;
  }

  record(callSign: string, phase: string, message: string): void {
    this.cache.set(callSign, {
      hash: this.hashMessage(phase, message),
      timestamp: Date.now()
    });
  }

  private hashMessage(phase: string, message: string): string {
    return createHash('sha256')
      .update(`${phase}:${message}`)
      .digest('hex')
      .substring(0, 16);  // Truncate for efficiency
  }
}
```

**Rationale**:
- Hash avoids storing full message text in memory
- Per-callsign deduplication (different agents can say same thing)
- TTL-based expiry; stale entries auto-expire on next check
- SHA256 truncated to 16 chars is sufficient for collision avoidance

**Alternatives Considered**:
- Store full message text: Privacy concern; unnecessary memory
- Global deduplication: Too restrictive across agents
- LRU cache: Overkill; single entry per callsign sufficient

---

## 5. Speech Queue Architecture

**Task**: Research sequential queue to prevent overlapping audio.

### Decision: Promise-based FIFO queue

**Implementation Pattern**:

```typescript
type QueueItem = {
  text: string;
  resolve: () => void;
  reject: (err: Error) => void;
};

class SpeechQueue {
  private queue: QueueItem[] = [];
  private processing = false;

  async enqueue(text: string): Promise<void> {
    return new Promise((resolve, reject) => {
      this.queue.push({ text, resolve, reject });
      this.processNext();
    });
  }

  private async processNext(): Promise<void> {
    if (this.processing || this.queue.length === 0) return;
    
    this.processing = true;
    const item = this.queue.shift()!;

    try {
      await speakViaPowerShell(item.text);
      item.resolve();
    } catch (err) {
      item.reject(err as Error);
    } finally {
      this.processing = false;
      this.processNext();  // Process next in queue
    }
  }

  get length(): number {
    return this.queue.length;
  }

  clear(): void {
    // Reject all pending
    for (const item of this.queue) {
      item.reject(new Error('Queue cleared'));
    }
    this.queue = [];
  }
}
```

**Rationale**:
- FIFO ensures messages play in order received
- Promise-based allows callers to await completion
- Single `processing` flag prevents concurrent speech
- Clear method for graceful shutdown

**Alternatives Considered**:
- Concurrent speech: Results in overlapping audio (unusable)
- Drop-on-busy: Loses messages; confusing for users
- Priority queue: Unnecessary complexity for status messages

---

## 6. Project Configuration

**Task**: Determine minimal TypeScript/Node.js project setup.

### Decision: Modern ESM with strict TypeScript

**tsconfig.json**:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "outDir": "dist",
    "rootDir": "src",
    "declaration": true
  },
  "include": ["src/**/*"]
}
```

**package.json** (key fields):
```json
{
  "name": "mcp-voice-status",
  "version": "1.0.0",
  "type": "module",
  "main": "dist/index.js",
  "bin": {
    "mcp-voice-status": "dist/index.js"
  },
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev": "tsx src/index.ts",
    "test": "vitest",
    "lint": "eslint src"
  },
  "engines": {
    "node": ">=20.0.0"
  }
}
```

**Rationale**:
- ESM (`"type": "module"`) is the modern standard
- `NodeNext` resolution handles `.js` extensions properly
- `strict: true` per Constitution development standards
- `tsx` for development (no build step needed)

---

## Summary

All technical unknowns have been resolved:

| Area | Decision | Constitution Compliance |
|------|----------|------------------------|
| MCP SDK | `McpServer` + `StdioServerTransport` | ✅ VI (minimal deps) |
| TTS | PowerShell `System.Speech` via `execFile` | ✅ I, VI (Windows-first, no native addons) |
| Rate Limiting | Per-callsign sliding window (3s default) | ✅ IV |
| Deduplication | Hash-based cache with 10s TTL | ✅ VII (simple) |
| Speech Queue | Promise-based FIFO queue | ✅ VII (simple) |
| Project Setup | ESM + strict TypeScript | ✅ Development Standards |
