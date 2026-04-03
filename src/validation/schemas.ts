/**
 * Zod validation schemas for MCP tool inputs.
 * Based on contracts/tools.json specification.
 */

import { z } from 'zod';
import {
  CALLSIGN_MIN_LENGTH,
  CALLSIGN_MAX_LENGTH,
  CALLSIGN_PATTERN,
  MESSAGE_MIN_LENGTH,
  MESSAGE_MAX_LENGTH,
  STATUS_PHASES,
} from '../types.js';

/**
 * Schema for validating call signs.
 * - Alphanumeric with optional hyphens
 * - 1-20 characters
 * - No leading/trailing hyphens
 */
export const callSignSchema = z
  .string()
  .min(CALLSIGN_MIN_LENGTH, 'Call sign must be at least 1 character')
  .max(CALLSIGN_MAX_LENGTH, 'Call sign must be at most 20 characters')
  .regex(
    CALLSIGN_PATTERN,
    'Call sign must be alphanumeric with optional hyphens (e.g., "Copilot", "Agent-7")'
  );

/**
 * Schema for status phase enumeration.
 */
export const statusPhaseSchema = z.enum(['confirm', 'waiting', 'blocked', 'done', 'error'], {
  errorMap: () => ({
    message: `Phase must be one of: ${STATUS_PHASES.join(', ')}`,
  }),
});

/**
 * Schema for message content.
 * - 1-200 characters
 * - Trimmed, non-empty
 */
export const messageSchema = z
  .string()
  .min(MESSAGE_MIN_LENGTH, 'Message cannot be empty')
  .max(MESSAGE_MAX_LENGTH, `Message must be at most ${MESSAGE_MAX_LENGTH} characters`)
  .transform((s) => s.trim())
  .refine((s) => s.length > 0, 'Message cannot be only whitespace');

/**
 * Schema for register_callsign tool input.
 */
export const registerCallSignInputSchema = z.object({
  callSign: callSignSchema,
});

/**
 * Schema for speak_status tool input.
 */
export const speakStatusInputSchema = z.object({
  phase: statusPhaseSchema,
  message: messageSchema,
  callSign: callSignSchema.optional(),
});

// Type exports inferred from schemas
export type CallSignInput = z.infer<typeof callSignSchema>;
export type StatusPhaseInput = z.infer<typeof statusPhaseSchema>;
export type MessageInput = z.infer<typeof messageSchema>;
export type RegisterCallSignInput = z.infer<typeof registerCallSignInputSchema>;
export type SpeakStatusInput = z.infer<typeof speakStatusInputSchema>;
