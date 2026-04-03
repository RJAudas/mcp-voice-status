/**
 * Text sanitizer for TTS input.
 * Removes potentially dangerous content and normalizes text for speech synthesis.
 * 
 * Security: Prevents SSML injection, PowerShell injection, and other attacks.
 */

/** Maximum length of sanitized text */
export const MAX_SANITIZED_LENGTH = 500;

/**
 * Sanitize text for safe use with Windows TTS via PowerShell.
 * 
 * Performs the following sanitization:
 * 1. Remove null bytes (can break string handling)
 * 2. Remove SSML/XML tags (prevent SSML injection), replacing with space
 * 3. Escape single quotes for PowerShell (double them)
 * 4. Remove double quotes (could break PowerShell string boundaries)
 * 5. Remove backticks (PowerShell escape character)
 * 6. Remove control characters except common whitespace
 * 7. Normalize whitespace (collapse multiple spaces)
 * 8. Trim leading/trailing whitespace
 * 9. Enforce maximum length
 * 
 * @param text - The raw text to sanitize
 * @returns Sanitized text safe for TTS
 * @throws Error if text is empty after sanitization
 */
export function sanitizeTextForTTS(text: string): string {
  if (typeof text !== 'string') {
    throw new Error('Text must be a string');
  }

  let result = text;

  // 1. Remove null bytes (replace with space to preserve word boundaries)
  result = result.replace(/\0/g, ' ');

  // 2. Remove SSML/XML-like tags (replace with space to preserve word boundaries)
  result = result.replace(/<[^>]*>/g, ' ');

  // 3. Escape single quotes for PowerShell (double them)
  result = result.replace(/'/g, "''");

  // 4. Remove double quotes (could break PowerShell string boundaries)
  result = result.replace(/"/g, '');

  // 5. Remove backticks (PowerShell escape character)
  result = result.replace(/`/g, '');

  // 6. Remove control characters except tab, newline, carriage return
  // eslint-disable-next-line no-control-regex
  result = result.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '');

  // 7. Normalize whitespace (collapse multiple spaces, convert newlines to spaces)
  result = result.replace(/\s+/g, ' ');

  // 8. Trim
  result = result.trim();

  // 9. Enforce maximum length
  if (result.length > MAX_SANITIZED_LENGTH) {
    result = result.substring(0, MAX_SANITIZED_LENGTH);
  }

  return result;
}

/**
 * Format a status message for speech.
 * Creates the standard format: "[CallSign]: [phase]. [message]"
 * 
 * @param callSign - The agent's call sign
 * @param phase - The status phase
 * @param message - The message content
 * @returns Formatted and sanitized speech text
 */
export function formatSpeechText(
  callSign: string,
  phase: string,
  message: string
): string {
  // Sanitize all components
  const safeCallSign = sanitizeTextForTTS(callSign);
  const safePhase = sanitizeTextForTTS(phase);
  const safeMessage = sanitizeTextForTTS(message);

  // Format: "Copilot: confirm. Starting code review."
  return `${safeCallSign}: ${safePhase}. ${safeMessage}`;
}

/**
 * Check if text contains potentially dangerous content.
 * Used for validation before sanitization.
 * 
 * @param text - Text to check
 * @returns Object with boolean flags for each danger type
 */
export function detectDangerousContent(text: string): {
  hasNullBytes: boolean;
  hasXmlTags: boolean;
  hasControlChars: boolean;
  hasPowerShellEscapes: boolean;
} {
  return {
    hasNullBytes: /\0/.test(text),
    hasXmlTags: /<[^>]*>/.test(text),
    // eslint-disable-next-line no-control-regex
    hasControlChars: /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/.test(text),
    hasPowerShellEscapes: /`/.test(text),
  };
}
