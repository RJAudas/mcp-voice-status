/**
 * Unit tests for rate limiter.
 * 
 * Tests per-callsign rate limiting, cooldown calculation,
 * and state management.
 */

import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import { RateLimiter } from '../../src/middleware/rate-limiter.js';

describe('RateLimiter', () => {
  let rateLimiter: RateLimiter;

  beforeEach(() => {
    vi.useFakeTimers();
    rateLimiter = new RateLimiter(3000); // 3 second interval
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  describe('constructor', () => {
    it('should use default interval when not specified', () => {
      const limiter = new RateLimiter();
      expect(limiter.interval).toBe(3000);
    });

    it('should accept custom interval', () => {
      const limiter = new RateLimiter(5000);
      expect(limiter.interval).toBe(5000);
    });

    it('should clamp interval to minimum 1000ms', () => {
      const limiter = new RateLimiter(500);
      expect(limiter.interval).toBe(1000);
    });

    it('should accept exactly 1000ms', () => {
      const limiter = new RateLimiter(1000);
      expect(limiter.interval).toBe(1000);
    });
  });

  describe('canSpeak', () => {
    it('should allow first message from new call sign', () => {
      expect(rateLimiter.canSpeak('Copilot')).toBe(true);
    });

    it('should allow first message from multiple call signs', () => {
      expect(rateLimiter.canSpeak('Copilot')).toBe(true);
      expect(rateLimiter.canSpeak('Claude')).toBe(true);
      expect(rateLimiter.canSpeak('Agent-7')).toBe(true);
    });

    it('should deny message immediately after speaking', () => {
      rateLimiter.recordSpoken('Copilot');
      expect(rateLimiter.canSpeak('Copilot')).toBe(false);
    });

    it('should allow message after cooldown expires', () => {
      rateLimiter.recordSpoken('Copilot');
      
      vi.advanceTimersByTime(3001);
      
      expect(rateLimiter.canSpeak('Copilot')).toBe(true);
    });

    it('should deny message before cooldown expires', () => {
      rateLimiter.recordSpoken('Copilot');
      
      vi.advanceTimersByTime(2999);
      
      expect(rateLimiter.canSpeak('Copilot')).toBe(false);
    });

    it('should track call signs independently', () => {
      rateLimiter.recordSpoken('Copilot');
      
      // Copilot should be rate limited
      expect(rateLimiter.canSpeak('Copilot')).toBe(false);
      
      // Other call signs should be fine
      expect(rateLimiter.canSpeak('Claude')).toBe(true);
      expect(rateLimiter.canSpeak('Agent-7')).toBe(true);
    });
  });

  describe('recordSpoken', () => {
    it('should update last spoken time', () => {
      rateLimiter.recordSpoken('Copilot');
      expect(rateLimiter.canSpeak('Copilot')).toBe(false);
      
      vi.advanceTimersByTime(3001);
      rateLimiter.recordSpoken('Copilot');
      
      expect(rateLimiter.canSpeak('Copilot')).toBe(false);
    });

    it('should create entry for new call sign', () => {
      expect(rateLimiter.size).toBe(0);
      rateLimiter.recordSpoken('Copilot');
      expect(rateLimiter.size).toBe(1);
    });
  });

  describe('getRemainingCooldown', () => {
    it('should return 0 for unknown call sign', () => {
      expect(rateLimiter.getRemainingCooldown('Unknown')).toBe(0);
    });

    it('should return full cooldown immediately after speaking', () => {
      rateLimiter.recordSpoken('Copilot');
      expect(rateLimiter.getRemainingCooldown('Copilot')).toBe(3000);
    });

    it('should return decreasing cooldown over time', () => {
      rateLimiter.recordSpoken('Copilot');
      
      vi.advanceTimersByTime(1000);
      expect(rateLimiter.getRemainingCooldown('Copilot')).toBe(2000);
      
      vi.advanceTimersByTime(1000);
      expect(rateLimiter.getRemainingCooldown('Copilot')).toBe(1000);
    });

    it('should return 0 after cooldown expires', () => {
      rateLimiter.recordSpoken('Copilot');
      
      vi.advanceTimersByTime(3001);
      
      expect(rateLimiter.getRemainingCooldown('Copilot')).toBe(0);
    });
  });

  describe('clear', () => {
    it('should remove all entries', () => {
      rateLimiter.recordSpoken('Copilot');
      rateLimiter.recordSpoken('Claude');
      
      expect(rateLimiter.size).toBe(2);
      
      rateLimiter.clear();
      
      expect(rateLimiter.size).toBe(0);
      expect(rateLimiter.canSpeak('Copilot')).toBe(true);
      expect(rateLimiter.canSpeak('Claude')).toBe(true);
    });
  });

  describe('clearCallSign', () => {
    it('should remove specific call sign entry', () => {
      rateLimiter.recordSpoken('Copilot');
      rateLimiter.recordSpoken('Claude');
      
      rateLimiter.clearCallSign('Copilot');
      
      expect(rateLimiter.canSpeak('Copilot')).toBe(true);
      expect(rateLimiter.canSpeak('Claude')).toBe(false);
    });

    it('should handle non-existent call sign gracefully', () => {
      expect(() => rateLimiter.clearCallSign('Unknown')).not.toThrow();
    });
  });

  describe('size', () => {
    it('should track number of entries', () => {
      expect(rateLimiter.size).toBe(0);
      
      rateLimiter.recordSpoken('A');
      expect(rateLimiter.size).toBe(1);
      
      rateLimiter.recordSpoken('B');
      expect(rateLimiter.size).toBe(2);
      
      rateLimiter.clearCallSign('A');
      expect(rateLimiter.size).toBe(1);
    });
  });
});
