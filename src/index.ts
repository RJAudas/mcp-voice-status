#!/usr/bin/env node
/**
 * MCP Voice Status Server
 * 
 * A local-only MCP server that enables VS Code agents to emit short spoken
 * status messages via Windows text-to-speech.
 * 
 * Tools:
 * - register_callsign: Register an agent's call sign
 * - speak_status: Speak a status message with the registered call sign
 */

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';

import {
  createInitialState,
  DEFAULT_CONFIG,
  ServerConfig,
  ServerState,
  StatusPhase,
} from './types.js';
import { callSignSchema, statusPhaseSchema, messageSchema } from './validation/schemas.js';
import { formatSpeechText } from './speech/sanitizer.js';
import { getSpeechQueue, resetSpeechQueue } from './speech/queue.js';
import { RateLimiter } from './middleware/rate-limiter.js';
import { Deduplicator } from './middleware/deduplicator.js';

// =============================================================================
// Logging (use stderr only - stdout reserved for MCP protocol)
// =============================================================================

function log(level: 'info' | 'warn' | 'error', message: string, data?: Record<string, unknown>): void {
  const timestamp = new Date().toISOString();
  const logEntry = {
    timestamp,
    level,
    message,
    ...data,
  };
  console.error(JSON.stringify(logEntry));
}

// =============================================================================
// Server State
// =============================================================================

let serverState: ServerState = createInitialState();
const serverConfig: ServerConfig = { ...DEFAULT_CONFIG };

// Initialize middleware
let rateLimiter = new RateLimiter(serverConfig.rateLimit.minIntervalMs);
let deduplicator = new Deduplicator(serverConfig.dedup.windowMs);

/**
 * Reset server state (for testing or re-initialization).
 */
export function resetServerState(): void {
  serverState = createInitialState();
  rateLimiter = new RateLimiter(serverConfig.rateLimit.minIntervalMs);
  deduplicator = new Deduplicator(serverConfig.dedup.windowMs);
  resetSpeechQueue();
}

// =============================================================================
// Environment Configuration
// =============================================================================

function loadConfigFromEnv(): void {
  // MCP_VOICE_DEFAULT_CALLSIGN - default call sign if none registered
  const defaultCallSign = process.env['MCP_VOICE_DEFAULT_CALLSIGN'];
  if (defaultCallSign) {
    try {
      callSignSchema.parse(defaultCallSign);
      serverConfig.defaultCallSign = defaultCallSign;
      log('info', 'Default call sign configured from environment', { callSign: defaultCallSign });
    } catch {
      log('warn', 'Invalid MCP_VOICE_DEFAULT_CALLSIGN, ignoring', { value: defaultCallSign });
    }
  }

  // MCP_VOICE_RATE_LIMIT_MS - minimum interval between messages
  const rateLimitMs = process.env['MCP_VOICE_RATE_LIMIT_MS'];
  if (rateLimitMs) {
    const parsed = parseInt(rateLimitMs, 10);
    if (!isNaN(parsed) && parsed >= 1000) {
      serverConfig.rateLimit.minIntervalMs = parsed;
      rateLimiter = new RateLimiter(parsed);
      log('info', 'Rate limit configured from environment', { minIntervalMs: parsed });
    }
  }

  // MCP_VOICE_DEDUP_WINDOW_MS - deduplication window
  const dedupWindowMs = process.env['MCP_VOICE_DEDUP_WINDOW_MS'];
  if (dedupWindowMs) {
    const parsed = parseInt(dedupWindowMs, 10);
    if (!isNaN(parsed) && parsed >= 0) {
      serverConfig.dedup.windowMs = parsed;
      deduplicator = new Deduplicator(parsed);
      log('info', 'Dedup window configured from environment', { windowMs: parsed });
    }
  }
}

// =============================================================================
// MCP Server Setup
// =============================================================================

const server = new McpServer({
  name: serverConfig.name,
  version: serverConfig.version,
});

// -----------------------------------------------------------------------------
// Tool: register_callsign
// -----------------------------------------------------------------------------

server.tool(
  'register_callsign',
  'Register an agent call sign for spoken status messages. Call signs identify who is speaking and must be registered before using speak_status.',
  {
    callSign: z.string().describe(
      "The call sign to register (e.g., 'Copilot', 'Claude', 'Agent-7'). Must be alphanumeric with optional hyphens, 1-20 characters."
    ),
  },
  async ({ callSign }) => {
    // Validate call sign
    const validationResult = callSignSchema.safeParse(callSign);
    if (!validationResult.success) {
      const errorMessage = validationResult.error.errors[0]?.message ?? 'Invalid call sign';
      log('warn', 'Invalid call sign rejected', { callSign, error: errorMessage });
      return {
        content: [{ type: 'text', text: JSON.stringify({ success: false, error: errorMessage }) }],
        isError: true,
      };
    }

    // Store previous call sign if any
    const previousCallSign = serverState.callSign?.value;

    // Register new call sign
    serverState.callSign = {
      value: validationResult.data,
      registeredAt: Date.now(),
    };

    log('info', 'Call sign registered', {
      callSign: validationResult.data,
      previousCallSign,
    });

    const response = {
      success: true,
      callSign: validationResult.data,
      ...(previousCallSign && { previousCallSign }),
    };

    return {
      content: [{ type: 'text', text: JSON.stringify(response) }],
    };
  }
);

// -----------------------------------------------------------------------------
// Tool: speak_status
// -----------------------------------------------------------------------------

server.tool(
  'speak_status',
  'Speak a short status message using Windows text-to-speech. Messages are prefixed with the registered call sign and status phase. Rate limiting and deduplication are applied automatically.',
  {
    phase: z.enum(['confirm', 'waiting', 'blocked', 'done', 'error']).describe(
      "Status phase: 'confirm' (acknowledge), 'waiting' (blocked state), 'blocked' (external dep), 'done' (complete), 'error' (failure)"
    ),
    message: z.string().describe(
      'The message content to speak. Should be 1-2 sentences maximum, factual and concise.'
    ),
    callSign: z.string().optional().describe(
      'Optional call sign override. If not provided, uses the registered call sign.'
    ),
  },
  async ({ phase, message, callSign: callSignOverride }) => {
    // Validate phase
    const phaseResult = statusPhaseSchema.safeParse(phase);
    if (!phaseResult.success) {
      return {
        content: [{ type: 'text', text: JSON.stringify({ spoken: false, error: 'Invalid phase' }) }],
        isError: true,
      };
    }

    // Validate message
    const messageResult = messageSchema.safeParse(message);
    if (!messageResult.success) {
      const errorMessage = messageResult.error.errors[0]?.message ?? 'Invalid message';
      return {
        content: [{ type: 'text', text: JSON.stringify({ spoken: false, error: errorMessage }) }],
        isError: true,
      };
    }

    // Determine call sign to use
    let effectiveCallSign: string | undefined;

    if (callSignOverride) {
      const overrideResult = callSignSchema.safeParse(callSignOverride);
      if (!overrideResult.success) {
        return {
          content: [{ type: 'text', text: JSON.stringify({ spoken: false, error: 'Invalid call sign override' }) }],
          isError: true,
        };
      }
      effectiveCallSign = overrideResult.data;
    } else {
      effectiveCallSign = serverState.callSign?.value ?? serverConfig.defaultCallSign;
    }

    // Check if we have a call sign
    if (!effectiveCallSign) {
      log('warn', 'No call sign available', { hasRegistered: !!serverState.callSign });
      return {
        content: [{
          type: 'text',
          text: JSON.stringify({
            spoken: false,
            skippedReason: 'no_callsign',
          }),
        }],
      };
    }

    // Check rate limiting
    if (!rateLimiter.canSpeak(effectiveCallSign)) {
      const cooldownMs = rateLimiter.getRemainingCooldown(effectiveCallSign);
      log('info', 'Message rate limited', { callSign: effectiveCallSign, cooldownMs });
      return {
        content: [{
          type: 'text',
          text: JSON.stringify({
            spoken: false,
            skippedReason: 'rate_limited',
            cooldownMs,
          }),
        }],
      };
    }

    // Check deduplication
    const validatedPhase = phaseResult.data as StatusPhase;
    const validatedMessage = messageResult.data;

    if (deduplicator.isDuplicate(effectiveCallSign, validatedPhase, validatedMessage)) {
      log('info', 'Message deduplicated', { callSign: effectiveCallSign, phase: validatedPhase });
      return {
        content: [{
          type: 'text',
          text: JSON.stringify({
            spoken: false,
            skippedReason: 'deduplicated',
          }),
        }],
      };
    }

    // Format the speech text
    const spokenText = formatSpeechText(effectiveCallSign, validatedPhase, validatedMessage);

    // Queue the speech
    try {
      const queue = getSpeechQueue();
      await queue.enqueue(spokenText, effectiveCallSign, validatedPhase);

      // Record for rate limiting and deduplication
      rateLimiter.recordSpoken(effectiveCallSign);
      deduplicator.record(effectiveCallSign, validatedPhase, validatedMessage);

      log('info', 'Message spoken', {
        callSign: effectiveCallSign,
        phase: validatedPhase,
        messageLength: validatedMessage.length,
      });

      return {
        content: [{
          type: 'text',
          text: JSON.stringify({
            spoken: true,
            spokenText,
          }),
        }],
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown TTS error';
      log('error', 'TTS failed', { callSign: effectiveCallSign, error: errorMessage });
      return {
        content: [{
          type: 'text',
          text: JSON.stringify({
            spoken: false,
            error: errorMessage,
          }),
        }],
        isError: true,
      };
    }
  }
);

// =============================================================================
// Main Entry Point
// =============================================================================

async function main(): Promise<void> {
  // Load configuration from environment
  loadConfigFromEnv();

  log('info', 'MCP Voice Status server starting', {
    name: serverConfig.name,
    version: serverConfig.version,
    rateLimitMs: serverConfig.rateLimit.minIntervalMs,
    dedupWindowMs: serverConfig.dedup.windowMs,
  });

  // Set up graceful shutdown
  const shutdown = async () => {
    log('info', 'Shutting down...');
    resetSpeechQueue();
    process.exit(0);
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);

  // Connect to stdio transport
  const transport = new StdioServerTransport();
  await server.connect(transport);

  log('info', 'MCP Voice Status server ready');
}

// Run if this is the main module
main().catch((error) => {
  log('error', 'Failed to start server', { error: String(error) });
  process.exit(1);
});
