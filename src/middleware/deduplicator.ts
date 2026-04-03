/**
 * Message deduplication to prevent repeating identical status messages.
 * 
 * Uses content hashing with a sliding time window to detect and
 * suppress duplicate messages from the same call sign.
 */

import { DedupeEntry, DEFAULT_DEDUP_WINDOW_MS } from '../types.js';

/**
 * Create a simple hash for deduplication.
 * Not cryptographic - just for quick comparison.
 */
function hashMessage(callSign: string, phase: string, message: string): string {
  // Simple string concatenation with delimiter
  // This is sufficient for deduplication purposes
  return `${callSign.toLowerCase()}|${phase.toLowerCase()}|${message.toLowerCase().trim()}`;
}

/**
 * Deduplicator using hash-based caching with time window.
 */
export class Deduplicator {
  private cache = new Map<string, DedupeEntry>();
  private windowMs: number;
  private cleanupIntervalId: ReturnType<typeof setInterval> | null = null;

  /**
   * Create a new deduplicator.
   * 
   * @param windowMs - Time window in milliseconds for deduplication.
   *                   Messages within this window are considered duplicates.
   */
  constructor(windowMs: number = DEFAULT_DEDUP_WINDOW_MS) {
    this.windowMs = Math.max(windowMs, 1000); // Minimum 1 second window
    this.startCleanup();
  }

  /**
   * Check if a message is a duplicate of a recent message.
   * 
   * @param callSign - The call sign speaking
   * @param phase - The status phase
   * @param message - The message content
   * @returns true if this is a duplicate, false if it's new
   */
  isDuplicate(callSign: string, phase: string, message: string): boolean {
    const hash = hashMessage(callSign, phase, message);
    const entry = this.cache.get(hash);

    if (!entry) {
      return false;
    }

    // Check if entry is still within the dedup window
    const age = Date.now() - entry.spokenAt;
    if (age >= this.windowMs) {
      // Entry has expired
      this.cache.delete(hash);
      return false;
    }

    return true;
  }

  /**
   * Record a message as spoken.
   * Call this after successfully speaking a message.
   * 
   * @param callSign - The call sign that spoke
   * @param phase - The status phase
   * @param message - The message content
   */
  record(callSign: string, phase: string, message: string): void {
    const hash = hashMessage(callSign, phase, message);
    this.cache.set(hash, {
      messageHash: hash,
      spokenAt: Date.now()
    });
  }

  /**
   * Check and record in one operation.
   * Returns true if the message was a duplicate.
   * If not a duplicate, records it and returns false.
   * 
   * @param callSign - The call sign speaking
   * @param phase - The status phase
   * @param message - The message content
   * @returns true if duplicate (message should be skipped), false if new (message recorded)
   */
  checkAndRecord(callSign: string, phase: string, message: string): boolean {
    if (this.isDuplicate(callSign, phase, message)) {
      return true;
    }
    this.record(callSign, phase, message);
    return false;
  }

  /**
   * Get the configured dedup window.
   */
  get window(): number {
    return this.windowMs;
  }

  /**
   * Clear all cached entries.
   */
  clear(): void {
    this.cache.clear();
  }

  /**
   * Get the number of cached entries.
   */
  get size(): number {
    return this.cache.size;
  }

  /**
   * Start periodic cleanup of expired entries.
   */
  private startCleanup(): void {
    // Run cleanup every window interval
    this.cleanupIntervalId = setInterval(() => {
      this.cleanup();
    }, this.windowMs);

    // Don't keep the process alive just for cleanup
    if (this.cleanupIntervalId.unref) {
      this.cleanupIntervalId.unref();
    }
  }

  /**
   * Remove expired entries from the cache.
   */
  private cleanup(): void {
    const now = Date.now();
    for (const [hash, entry] of this.cache) {
      if (now - entry.spokenAt >= this.windowMs) {
        this.cache.delete(hash);
      }
    }
  }

  /**
   * Stop the cleanup interval.
   * Call this before discarding the deduplicator.
   */
  dispose(): void {
    if (this.cleanupIntervalId) {
      clearInterval(this.cleanupIntervalId);
      this.cleanupIntervalId = null;
    }
  }
}
