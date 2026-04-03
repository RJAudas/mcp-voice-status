/**
 * Unit tests for text sanitizer.
 * 
 * Tests SSML removal, quote escaping, control character filtering,
 * and message formatting.
 */

import { describe, it, expect } from 'vitest';
import { sanitizeTextForTTS, formatSpeechText } from '../../src/speech/sanitizer.js';

describe('sanitizeTextForTTS', () => {
  describe('basic text', () => {
    it('should pass through plain text unchanged', () => {
      expect(sanitizeTextForTTS('Hello world')).toBe('Hello world');
    });

    it('should preserve normal punctuation', () => {
      expect(sanitizeTextForTTS('Hello, world!')).toBe('Hello, world!');
    });

    it('should trim leading and trailing whitespace', () => {
      expect(sanitizeTextForTTS('  Hello world  ')).toBe('Hello world');
    });

    it('should handle empty string', () => {
      expect(sanitizeTextForTTS('')).toBe('');
    });

    it('should handle whitespace-only string', () => {
      expect(sanitizeTextForTTS('   ')).toBe('');
    });
  });

  describe('SSML removal', () => {
    it('should remove simple SSML tags', () => {
      expect(sanitizeTextForTTS('<speak>Hello</speak>')).toBe('Hello');
    });

    it('should remove SSML emphasis tags', () => {
      expect(sanitizeTextForTTS('<emphasis>important</emphasis>')).toBe('important');
    });

    it('should remove SSML break tags', () => {
      expect(sanitizeTextForTTS('Hello<break time="500ms"/>world')).toBe('Hello world');
    });

    it('should remove self-closing SSML tags', () => {
      expect(sanitizeTextForTTS('Hello<break/>world')).toBe('Hello world');
    });

    it('should remove nested SSML tags', () => {
      expect(sanitizeTextForTTS('<speak><voice name="en-US-Standard">Hello</voice></speak>')).toBe('Hello');
    });

    it('should remove SSML tags with attributes', () => {
      expect(sanitizeTextForTTS('<prosody rate="fast">Quick message</prosody>')).toBe('Quick message');
    });
  });

  describe('quote handling', () => {
    it('should escape double quotes', () => {
      const result = sanitizeTextForTTS('He said "hello"');
      expect(result).not.toContain('"');
    });

    it('should escape single quotes for PowerShell', () => {
      const result = sanitizeTextForTTS("It's working");
      expect(result).toBe("It''s working");
    });

    it('should handle multiple quotes', () => {
      const result = sanitizeTextForTTS("He said \"It's great\"");
      expect(result).not.toContain('"');
      expect(result).toContain("''");
    });
  });

  describe('control characters', () => {
    it('should remove null bytes', () => {
      expect(sanitizeTextForTTS('Hello\x00world')).toBe('Hello world');
    });

    it('should remove carriage returns', () => {
      expect(sanitizeTextForTTS('Hello\rworld')).toBe('Hello world');
    });

    it('should replace tabs with spaces', () => {
      expect(sanitizeTextForTTS('Hello\tworld')).toBe('Hello world');
    });

    it('should collapse multiple newlines', () => {
      expect(sanitizeTextForTTS('Hello\n\n\nworld')).toBe('Hello world');
    });

    it('should collapse multiple spaces', () => {
      expect(sanitizeTextForTTS('Hello     world')).toBe('Hello world');
    });
  });

  describe('edge cases', () => {
    it('should handle mixed SSML and control characters', () => {
      const input = '<speak>Hello\x00<break/>world</speak>';
      const result = sanitizeTextForTTS(input);
      expect(result).toBe('Hello world');
    });

    it('should handle unicode characters', () => {
      expect(sanitizeTextForTTS('Hello 世界')).toBe('Hello 世界');
    });

    it('should handle emoji', () => {
      // TTS might not speak emoji well, but sanitizer should pass them through
      expect(sanitizeTextForTTS('Done! ✓')).toBe('Done! ✓');
    });
  });
});

describe('formatSpeechText', () => {
  describe('basic formatting', () => {
    it('should format with call sign and phase', () => {
      const result = formatSpeechText('Copilot', 'confirm', 'Starting analysis');
      expect(result).toBe('Copilot: confirm. Starting analysis');
    });

    it('should work with all phases', () => {
      const phases = ['confirm', 'waiting', 'blocked', 'done', 'error'] as const;
      
      for (const phase of phases) {
        const result = formatSpeechText('Agent', phase, 'Test message');
        expect(result).toContain(`Agent: ${phase}. Test message`);
      }
    });

    it('should handle call sign with hyphen', () => {
      const result = formatSpeechText('Agent-7', 'done', 'Task complete');
      expect(result).toBe('Agent-7: done. Task complete');
    });
  });

  describe('message sanitization', () => {
    it('should sanitize the message content', () => {
      const result = formatSpeechText('Copilot', 'confirm', 'Check "this" file');
      expect(result).not.toContain('"');
    });

    it('should sanitize call sign', () => {
      const result = formatSpeechText('Agent"Test', 'confirm', 'Hello');
      expect(result).not.toContain('"');
    });

    it('should handle message with SSML', () => {
      const result = formatSpeechText('Copilot', 'done', '<emphasis>Complete</emphasis>');
      expect(result).not.toContain('<');
      expect(result).not.toContain('>');
    });
  });

  describe('whitespace handling', () => {
    it('should trim message whitespace', () => {
      const result = formatSpeechText('Copilot', 'done', '  Finished  ');
      expect(result).toBe('Copilot: done. Finished');
    });

    it('should handle message with internal whitespace', () => {
      const result = formatSpeechText('Copilot', 'confirm', 'Starting   task');
      expect(result).toBe('Copilot: confirm. Starting task');
    });
  });
});
