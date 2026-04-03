/**
 * Unit tests for Zod validation schemas.
 * 
 * Tests call sign, phase, and message validation rules.
 */

import { describe, it, expect } from 'vitest';
import {
  callSignSchema,
  statusPhaseSchema,
  messageSchema,
  registerCallSignInputSchema,
  speakStatusInputSchema,
} from '../../src/validation/schemas.js';

describe('callSignSchema', () => {
  describe('valid call signs', () => {
    const validCallSigns = [
      'Copilot',
      'Claude',
      'Agent7',
      'Agent-7',
      'My-Agent-Name',
      'A',
      '12345',
      'Agent-2-Beta',
      'X',
      'Agent123',
    ];

    it.each(validCallSigns)('should accept valid call sign: %s', (callSign) => {
      expect(callSignSchema.safeParse(callSign).success).toBe(true);
    });

    it('should accept exactly 20 character call sign', () => {
      const maxLength = 'A'.repeat(20);
      expect(callSignSchema.safeParse(maxLength).success).toBe(true);
    });
  });

  describe('invalid call signs', () => {
    it('should reject empty string', () => {
      const result = callSignSchema.safeParse('');
      expect(result.success).toBe(false);
    });

    it('should reject leading hyphen', () => {
      const result = callSignSchema.safeParse('-Agent');
      expect(result.success).toBe(false);
    });

    it('should reject trailing hyphen', () => {
      const result = callSignSchema.safeParse('Agent-');
      expect(result.success).toBe(false);
    });

    it('should reject consecutive hyphens', () => {
      const result = callSignSchema.safeParse('Agent--7');
      expect(result.success).toBe(false);
    });

    it('should reject special characters', () => {
      const invalidChars = ['Agent!', 'Agent@Bot', 'My Agent', 'Agent_1', 'Agent.1'];
      for (const invalid of invalidChars) {
        expect(callSignSchema.safeParse(invalid).success).toBe(false);
      }
    });

    it('should reject call sign over 20 characters', () => {
      const tooLong = 'A'.repeat(21);
      expect(callSignSchema.safeParse(tooLong).success).toBe(false);
    });

    it('should reject non-string input', () => {
      expect(callSignSchema.safeParse(123).success).toBe(false);
      expect(callSignSchema.safeParse(null).success).toBe(false);
      expect(callSignSchema.safeParse(undefined).success).toBe(false);
    });
  });
});

describe('statusPhaseSchema', () => {
  describe('valid phases', () => {
    const validPhases = ['confirm', 'waiting', 'blocked', 'done', 'error'];

    it.each(validPhases)('should accept valid phase: %s', (phase) => {
      expect(statusPhaseSchema.safeParse(phase).success).toBe(true);
    });
  });

  describe('invalid phases', () => {
    const invalidPhases = [
      'invalid',
      'CONFIRM',
      'Confirm',
      '',
      'pending',
      'success',
      'failure',
    ];

    it.each(invalidPhases)('should reject invalid phase: %s', (phase) => {
      expect(statusPhaseSchema.safeParse(phase).success).toBe(false);
    });

    it('should reject non-string input', () => {
      expect(statusPhaseSchema.safeParse(123).success).toBe(false);
      expect(statusPhaseSchema.safeParse(null).success).toBe(false);
    });

    it('should provide helpful error message', () => {
      const result = statusPhaseSchema.safeParse('invalid');
      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error.errors[0].message).toContain('confirm');
        expect(result.error.errors[0].message).toContain('done');
      }
    });
  });
});

describe('messageSchema', () => {
  describe('valid messages', () => {
    it('should accept normal message', () => {
      const result = messageSchema.safeParse('Starting analysis of the file.');
      expect(result.success).toBe(true);
    });

    it('should accept single character', () => {
      const result = messageSchema.safeParse('X');
      expect(result.success).toBe(true);
    });

    it('should accept 200 character message', () => {
      const maxLength = 'A'.repeat(200);
      const result = messageSchema.safeParse(maxLength);
      expect(result.success).toBe(true);
    });

    it('should trim and accept message with leading/trailing whitespace', () => {
      const result = messageSchema.safeParse('  Hello world  ');
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toBe('Hello world');
      }
    });
  });

  describe('invalid messages', () => {
    it('should reject empty string', () => {
      const result = messageSchema.safeParse('');
      expect(result.success).toBe(false);
    });

    it('should reject whitespace-only string', () => {
      const result = messageSchema.safeParse('   ');
      expect(result.success).toBe(false);
    });

    it('should reject message over 200 characters', () => {
      const tooLong = 'A'.repeat(201);
      const result = messageSchema.safeParse(tooLong);
      expect(result.success).toBe(false);
    });

    it('should reject non-string input', () => {
      expect(messageSchema.safeParse(123).success).toBe(false);
      expect(messageSchema.safeParse(null).success).toBe(false);
      expect(messageSchema.safeParse(undefined).success).toBe(false);
    });
  });
});

describe('registerCallSignInputSchema', () => {
  it('should validate complete input', () => {
    const result = registerCallSignInputSchema.safeParse({
      callSign: 'Copilot',
    });
    expect(result.success).toBe(true);
  });

  it('should reject missing callSign', () => {
    const result = registerCallSignInputSchema.safeParse({});
    expect(result.success).toBe(false);
  });

  it('should reject invalid callSign', () => {
    const result = registerCallSignInputSchema.safeParse({
      callSign: 'Invalid Call Sign!',
    });
    expect(result.success).toBe(false);
  });
});

describe('speakStatusInputSchema', () => {
  it('should validate complete input without override', () => {
    const result = speakStatusInputSchema.safeParse({
      phase: 'confirm',
      message: 'Starting task',
    });
    expect(result.success).toBe(true);
  });

  it('should validate complete input with callSign override', () => {
    const result = speakStatusInputSchema.safeParse({
      phase: 'done',
      message: 'Task complete',
      callSign: 'Agent-7',
    });
    expect(result.success).toBe(true);
  });

  it('should reject missing phase', () => {
    const result = speakStatusInputSchema.safeParse({
      message: 'Test message',
    });
    expect(result.success).toBe(false);
  });

  it('should reject missing message', () => {
    const result = speakStatusInputSchema.safeParse({
      phase: 'confirm',
    });
    expect(result.success).toBe(false);
  });

  it('should reject invalid phase', () => {
    const result = speakStatusInputSchema.safeParse({
      phase: 'invalid',
      message: 'Test message',
    });
    expect(result.success).toBe(false);
  });

  it('should reject invalid callSign override', () => {
    const result = speakStatusInputSchema.safeParse({
      phase: 'confirm',
      message: 'Test message',
      callSign: 'Invalid!',
    });
    expect(result.success).toBe(false);
  });
});
