/**
 * Per-callsign rate limiter for speech messages.
 * 
 * Enforces a minimum interval between spoken messages per call sign
 * to prevent audio spam.
 */

import { RateLimitEntry, DEFAULT_RATE_LIMIT_MS, MIN_RATE_LIMIT_MS } from '../types.js';

/**
 * Rate limiter using sliding window per call sign.
 */
export class RateLimiter {
  private entries = new Map<string, RateLimitEntry>();
  private minIntervalMs: number;

  /**
   * Create a new rate limiter.
   * 
   * @param minIntervalMs - Minimum interval between messages in milliseconds.
   *                        Will be clamped to MIN_RATE_LIMIT_MS minimum.
   */
  constructor(minIntervalMs: number = DEFAULT_RATE_LIMIT_MS) {
    this.minIntervalMs = Math.max(minIntervalMs, MIN_RATE_LIMIT_MS);
  }

  /**
   * Check if a call sign can speak (not rate limited).
   * 
   * @param callSign - The call sign to check
   * @returns true if the call sign can speak, false if rate limited
   */
  canSpeak(callSign: string): boolean {
    const now = Date.now();
    const entry = this.entries.get(callSign);

    if (!entry) {
      return true;
    }

    return now - entry.lastSpokenAt >= this.minIntervalMs;
  }

  /**
   * Record that a call sign has spoken.
   * Call this after successfully speaking a message.
   * 
   * @param callSign - The call sign that spoke
   */
  recordSpoken(callSign: string): void {
    this.entries.set(callSign, { lastSpokenAt: Date.now() });
  }

  /**
   * Get the remaining cooldown time for a call sign.
   * 
   * @param callSign - The call sign to check
   * @returns Remaining cooldown in milliseconds, or 0 if not rate limited
   */
  getRemainingCooldown(callSign: string): number {
    const entry = this.entries.get(callSign);
    if (!entry) {
      return 0;
    }

    const elapsed = Date.now() - entry.lastSpokenAt;
    return Math.max(0, this.minIntervalMs - elapsed);
  }

  /**
   * Get the configured minimum interval.
   */
  get interval(): number {
    return this.minIntervalMs;
  }

  /**
   * Clear all rate limit entries.
   */
  clear(): void {
    this.entries.clear();
  }

  /**
   * Clear rate limit entry for a specific call sign.
   * 
   * @param callSign - The call sign to clear
   */
  clearCallSign(callSign: string): void {
    this.entries.delete(callSign);
  }

  /**
   * Get the number of tracked call signs.
   */
  get size(): number {
    return this.entries.size;
  }
}
