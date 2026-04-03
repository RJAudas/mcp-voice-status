/**
 * Unit tests for deduplicator.
 * 
 * Tests duplicate detection, TTL expiry, and hash-based comparison.
 */

import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import { Deduplicator } from '../../src/middleware/deduplicator.js';

describe('Deduplicator', () => {
  let deduplicator: Deduplicator;

  beforeEach(() => {
    vi.useFakeTimers();
    deduplicator = new Deduplicator(10000); // 10 second window
  });

  afterEach(() => {
    deduplicator.dispose();
    vi.useRealTimers();
  });

  describe('constructor', () => {
    it('should use default window when not specified', () => {
      const d = new Deduplicator();
      expect(d.window).toBe(10000);
      d.dispose();
    });

    it('should accept custom window', () => {
      const d = new Deduplicator(5000);
      expect(d.window).toBe(5000);
      d.dispose();
    });

    it('should clamp window to minimum 1000ms', () => {
      const d = new Deduplicator(500);
      expect(d.window).toBe(1000);
      d.dispose();
    });
  });

  describe('isDuplicate', () => {
    it('should return false for new message', () => {
      expect(deduplicator.isDuplicate('Copilot', 'confirm', 'Hello')).toBe(false);
    });

    it('should return true for duplicate message', () => {
      deduplicator.record('Copilot', 'confirm', 'Hello');
      expect(deduplicator.isDuplicate('Copilot', 'confirm', 'Hello')).toBe(true);
    });

    it('should return false for different call sign', () => {
      deduplicator.record('Copilot', 'confirm', 'Hello');
      expect(deduplicator.isDuplicate('Claude', 'confirm', 'Hello')).toBe(false);
    });

    it('should return false for different phase', () => {
      deduplicator.record('Copilot', 'confirm', 'Hello');
      expect(deduplicator.isDuplicate('Copilot', 'done', 'Hello')).toBe(false);
    });

    it('should return false for different message', () => {
      deduplicator.record('Copilot', 'confirm', 'Hello');
      expect(deduplicator.isDuplicate('Copilot', 'confirm', 'World')).toBe(false);
    });

    it('should be case-insensitive', () => {
      deduplicator.record('Copilot', 'confirm', 'Hello');
      expect(deduplicator.isDuplicate('COPILOT', 'CONFIRM', 'HELLO')).toBe(true);
    });

    it('should trim whitespace for comparison', () => {
      deduplicator.record('Copilot', 'confirm', '  Hello  ');
      expect(deduplicator.isDuplicate('Copilot', 'confirm', 'hello')).toBe(true);
    });
  });

  describe('TTL expiry', () => {
    it('should return false after window expires', () => {
      deduplicator.record('Copilot', 'confirm', 'Hello');
      
      vi.advanceTimersByTime(10001);
      
      expect(deduplicator.isDuplicate('Copilot', 'confirm', 'Hello')).toBe(false);
    });

    it('should return true before window expires', () => {
      deduplicator.record('Copilot', 'confirm', 'Hello');
      
      vi.advanceTimersByTime(9999);
      
      expect(deduplicator.isDuplicate('Copilot', 'confirm', 'Hello')).toBe(true);
    });

    it('should handle multiple messages with different expiry times', () => {
      deduplicator.record('Copilot', 'confirm', 'First');
      
      vi.advanceTimersByTime(5000);
      deduplicator.record('Copilot', 'confirm', 'Second');
      
      // First is 5s old, Second is 0s old
      vi.advanceTimersByTime(5001);
      
      // First should be expired (10001ms old)
      expect(deduplicator.isDuplicate('Copilot', 'confirm', 'First')).toBe(false);
      // Second should still be valid (5001ms old)
      expect(deduplicator.isDuplicate('Copilot', 'confirm', 'Second')).toBe(true);
    });
  });

  describe('record', () => {
    it('should add new entry', () => {
      expect(deduplicator.size).toBe(0);
      deduplicator.record('Copilot', 'confirm', 'Hello');
      expect(deduplicator.size).toBe(1);
    });

    it('should update timestamp for existing entry', () => {
      deduplicator.record('Copilot', 'confirm', 'Hello');
      
      vi.advanceTimersByTime(9000);
      
      // Re-record refreshes the timestamp
      deduplicator.record('Copilot', 'confirm', 'Hello');
      
      vi.advanceTimersByTime(2000);
      
      // Should still be valid because we refreshed 2s ago
      expect(deduplicator.isDuplicate('Copilot', 'confirm', 'Hello')).toBe(true);
    });
  });

  describe('checkAndRecord', () => {
    it('should return false and record for new message', () => {
      const result = deduplicator.checkAndRecord('Copilot', 'confirm', 'Hello');
      expect(result).toBe(false);
      expect(deduplicator.size).toBe(1);
    });

    it('should return true for duplicate without re-recording', () => {
      deduplicator.checkAndRecord('Copilot', 'confirm', 'Hello');
      const result = deduplicator.checkAndRecord('Copilot', 'confirm', 'Hello');
      expect(result).toBe(true);
    });
  });

  describe('clear', () => {
    it('should remove all entries', () => {
      deduplicator.record('Copilot', 'confirm', 'Hello');
      deduplicator.record('Claude', 'done', 'World');
      
      expect(deduplicator.size).toBe(2);
      
      deduplicator.clear();
      
      expect(deduplicator.size).toBe(0);
      expect(deduplicator.isDuplicate('Copilot', 'confirm', 'Hello')).toBe(false);
    });
  });

  describe('cleanup', () => {
    it('should automatically clean up expired entries', () => {
      deduplicator.record('Copilot', 'confirm', 'Hello');
      
      expect(deduplicator.size).toBe(1);
      
      // Advance time past window plus cleanup interval
      vi.advanceTimersByTime(20001);
      
      // Cleanup should have run and removed expired entry
      expect(deduplicator.size).toBe(0);
    });
  });

  describe('dispose', () => {
    it('should stop cleanup interval', () => {
      const d = new Deduplicator(1000);
      d.record('Copilot', 'confirm', 'Hello');
      
      d.dispose();
      
      // Should not throw after dispose
      expect(() => d.isDuplicate('Copilot', 'confirm', 'Hello')).not.toThrow();
    });

    it('should be safe to call multiple times', () => {
      const d = new Deduplicator();
      d.dispose();
      expect(() => d.dispose()).not.toThrow();
    });
  });
});
