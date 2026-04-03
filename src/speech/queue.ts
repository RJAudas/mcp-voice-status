/**
 * Sequential speech queue to prevent overlapping audio.
 * 
 * Implements a FIFO queue that processes speech requests one at a time,
 * ensuring messages don't overlap and are spoken in order received.
 */

import { SpeechQueueItem, StatusPhase } from '../types.js';
import { speakText } from './tts.js';

/**
 * Speech queue for sequential TTS processing.
 */
export class SpeechQueue {
  private queue: SpeechQueueItem[] = [];
  private processing = false;

  /**
   * Enqueue text to be spoken.
   * Returns a promise that resolves when the text has been spoken.
   * 
   * @param text - Pre-sanitized text to speak
   * @param callSign - Call sign of the requesting agent
   * @param phase - Status phase of the message
   * @returns Promise that resolves when speech completes
   */
  async enqueue(
    text: string,
    callSign: string,
    phase: StatusPhase
  ): Promise<void> {
    return new Promise((resolve, reject) => {
      const item: SpeechQueueItem = {
        text,
        callSign,
        phase,
        queuedAt: Date.now(),
        resolve,
        reject,
      };

      this.queue.push(item);
      this.processNext();
    });
  }

  /**
   * Process the next item in the queue.
   * Only processes if not already processing and queue has items.
   */
  private async processNext(): Promise<void> {
    if (this.processing || this.queue.length === 0) {
      return;
    }

    this.processing = true;
    const item = this.queue.shift();

    if (!item) {
      this.processing = false;
      return;
    }

    try {
      await speakText(item.text);
      item.resolve();
    } catch (error) {
      item.reject(error instanceof Error ? error : new Error(String(error)));
    } finally {
      this.processing = false;
      // Process next item if any
      this.processNext();
    }
  }

  /**
   * Get the current queue length.
   */
  get length(): number {
    return this.queue.length;
  }

  /**
   * Check if the queue is currently processing.
   */
  get isProcessing(): boolean {
    return this.processing;
  }

  /**
   * Clear all pending items from the queue.
   * Rejects all pending promises with a cancellation error.
   */
  clear(): void {
    const error = new Error('Speech queue cleared');
    for (const item of this.queue) {
      item.reject(error);
    }
    this.queue = [];
  }

  /**
   * Get queue statistics.
   */
  getStats(): {
    queueLength: number;
    isProcessing: boolean;
    oldestItemAge: number | null;
  } {
    const oldestItem = this.queue[0];
    return {
      queueLength: this.queue.length,
      isProcessing: this.processing,
      oldestItemAge: oldestItem ? Date.now() - oldestItem.queuedAt : null,
    };
  }
}

// Singleton instance for the server
let globalQueue: SpeechQueue | null = null;

/**
 * Get the global speech queue instance.
 */
export function getSpeechQueue(): SpeechQueue {
  globalQueue ??= new SpeechQueue();
  return globalQueue;
}

/**
 * Reset the global speech queue (for testing).
 */
export function resetSpeechQueue(): void {
  if (globalQueue) {
    globalQueue.clear();
  }
  globalQueue = null;
}
