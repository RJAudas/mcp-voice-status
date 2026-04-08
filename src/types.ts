/**
 * MCP Voice Status Server - Shared Types
 * 
 * All TypeScript interfaces and types for the voice status server.
 * Based on data-model.md specification.
 */

// =============================================================================
// Core Types
// =============================================================================

/**
 * Valid status phases for spoken messages.
 * Maps to Constitution III structured status phases.
 */
export type StatusPhase = 'confirm' | 'waiting' | 'blocked' | 'done' | 'error';

export const STATUS_PHASES: readonly StatusPhase[] = [
  'confirm',
  'waiting',
  'blocked',
  'done',
  'error',
] as const;

/**
 * Call sign validation rules:
 * - Alphanumeric with optional hyphens
 * - 1-20 characters
 * - No leading/trailing hyphens
 */
export interface CallSignConfig {
  /** The call sign string (e.g., "Copilot", "Agent-7") */
  value: string;
  /** Timestamp when registered */
  registeredAt: number;
}

// Validation constants
export const CALLSIGN_MIN_LENGTH = 1;
export const CALLSIGN_MAX_LENGTH = 20;
export const CALLSIGN_PATTERN = /^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$/;

// Message constants
export const MESSAGE_MIN_LENGTH = 1;
export const MESSAGE_MAX_LENGTH = 200;

// =============================================================================
// Request/Response Types
// =============================================================================

/**
 * Request to speak a status message.
 */
export interface SpeakStatusRequest {
  /** Status phase category */
  phase: StatusPhase;

  /**
   * Message content (1-2 sentences).
   * Will be prefixed with call sign and phase.
   */
  message: string;

  /**
   * Optional call sign override.
   * If not provided, uses the registered call sign.
   */
  callSign?: string;
}

/**
 * Response from speak_status tool.
 */
export interface SpeakStatusResponse {
  /** Whether the message was spoken */
  spoken: boolean;

  /**
   * If not spoken, the reason why:
   * - 'rate_limited': Exceeded rate limit
   * - 'deduplicated': Duplicate message filtered
   * - 'no_callsign': No call sign registered
   */
  skippedReason?: 'rate_limited' | 'deduplicated' | 'no_callsign';

  /** Cooldown remaining in ms (if rate limited) */
  cooldownMs?: number;

  /** The full text that was spoken (for debugging) */
  spokenText?: string;
}

/**
 * Request to register an agent call sign.
 */
export interface RegisterCallSignRequest {
  /**
   * The call sign to register.
   * Must match CALLSIGN_PATTERN.
   */
  callSign: string;
}

/**
 * Response from register_callsign tool.
 */
export interface RegisterCallSignResponse {
  /** Whether registration succeeded */
  success: boolean;

  /** The registered call sign */
  callSign: string;

  /** Previous call sign if one was replaced */
  previousCallSign?: string;
}

// =============================================================================
// Internal State Types
// =============================================================================

/**
 * Rate limiter entry for a single call sign.
 */
export interface RateLimitEntry {
  /** Timestamp of last spoken message */
  lastSpokenAt: number;
}

/**
 * Rate limiter configuration.
 */
export interface RateLimiterConfig {
  /** Minimum interval between messages in milliseconds */
  minIntervalMs: number;
}

// Default configuration per Constitution IV
export const DEFAULT_RATE_LIMIT_MS = 3000; // 3 seconds
export const MIN_RATE_LIMIT_MS = 1000; // 1 second minimum

/**
 * Deduplication cache entry for a single call sign.
 */
export interface DedupeEntry {
  /** Hash of the last message (phase + content) */
  messageHash: string;

  /** Timestamp when the message was spoken */
  spokenAt: number;
}

/**
 * Deduplicator configuration.
 */
export interface DeduplicatorConfig {
  /** Time window for deduplication in milliseconds */
  windowMs: number;
}

// Default configuration
export const DEFAULT_DEDUP_WINDOW_MS = 10000; // 10 seconds

/**
 * Queued speech item.
 */
export interface SpeechQueueItem {
  /** Full text to speak (including call sign prefix) */
  text: string;

  /** Call sign of the requesting agent */
  callSign: string;

  /** Status phase */
  phase: StatusPhase;

  /** Optional TTS overrides for this queue item */
  ttsConfig?: Partial<TTSConfig>;

  /** Timestamp when queued */
  queuedAt: number;

  /** Promise resolution callback */
  resolve: () => void;

  /** Promise rejection callback */
  reject: (error: Error) => void;
}

// =============================================================================
// Server State
// =============================================================================

/**
 * Runtime state for the MCP Voice Status server.
 * All state is in-memory; nothing is persisted.
 */
export interface ServerState {
  /** Currently registered call sign (single agent) */
  callSign: CallSignConfig | null;

  /** Rate limit entries by call sign */
  rateLimits: Map<string, RateLimitEntry>;

  /** Deduplication entries by call sign */
  dedupeCache: Map<string, DedupeEntry>;

  /** Whether the speech queue is currently processing */
  speechQueueActive: boolean;
}

/**
 * Initial server state.
 */
export function createInitialState(): ServerState {
  return {
    callSign: null,
    rateLimits: new Map(),
    dedupeCache: new Map(),
    speechQueueActive: false,
  };
}

// =============================================================================
// Configuration Types
// =============================================================================

/**
 * TTS-specific configuration.
 */
export interface TTSConfig {
  /** Timeout for PowerShell TTS process in ms */
  timeoutMs: number;

  /** Speech rate (-10 to 10, 0 is normal) */
  rate: number;

  /** Volume (0 to 100) */
  volume: number;
}

/**
 * Agent-facing automation settings for contextual spoken updates.
 * These settings are intended for instructions and future UI surfaces.
 */
export interface AutomationCalloutsConfig {
  /** Announce the start of a meaningful task */
  taskStart: boolean;

  /** Announce meaningful progress changes, not every tool call */
  progressMilestones: boolean;

  /** Announce when the agent is waiting on user input */
  waiting: boolean;

  /** Announce successful completion */
  completion: boolean;

  /** Prefer narrating the concise result or answer in completion callouts */
  outcomeNarration: boolean;

  /** Announce failures and blocked states */
  errors: boolean;

  /** Whether to narrate low-value tool churn such as routine reads */
  lowValueToolUpdates: boolean;
}

/**
 * Instruction-driven automation configuration.
 */
export interface AutomationConfig {
  /** Whether contextual voice automation is enabled */
  enabled: boolean;

  /** Automation mode, reserved for future expansion */
  mode: 'instructions';

  /** Preferred call sign for agent-authored updates */
  callSign?: string;

  /** Enabled contextual callout categories */
  callouts: AutomationCalloutsConfig;
}

/**
 * Checked-in configuration file structure.
 */
export interface VoiceStatusConfigFile {
  speech?: Partial<TTSConfig> & {
    defaultCallSign?: string;
    rateLimitMs?: number;
    dedupWindowMs?: number;
  };
  automation?: Partial<Omit<AutomationConfig, 'callouts'>> & {
    callouts?: Partial<AutomationCalloutsConfig>;
  };
}

/**
 * Server configuration options.
 */
export interface ServerConfig {
  /** Server name for MCP protocol */
  name: string;

  /** Server version */
  version: string;

  /** Default call sign (optional) */
  defaultCallSign?: string;

  /** Rate limiting configuration */
  rateLimit: RateLimiterConfig;

  /** Deduplication configuration */
  dedup: DeduplicatorConfig;

  /** TTS configuration */
  tts: TTSConfig;
}

// Default configuration
export const DEFAULT_CONFIG: ServerConfig = {
  name: 'mcp-voice-status',
  version: '1.0.0',
  defaultCallSign: undefined,
  rateLimit: {
    minIntervalMs: DEFAULT_RATE_LIMIT_MS,
  },
  dedup: {
    windowMs: DEFAULT_DEDUP_WINDOW_MS,
  },
  tts: {
    timeoutMs: 30000,
    rate: 0,
    volume: 100,
  },
};

export const DEFAULT_AUTOMATION_CONFIG: AutomationConfig = {
  enabled: true,
  mode: 'instructions',
  callSign: 'Copilot',
  callouts: {
    taskStart: true,
    progressMilestones: true,
    waiting: true,
    completion: true,
    outcomeNarration: true,
    errors: true,
    lowValueToolUpdates: false,
  },
};

// =============================================================================
// Error Types
// =============================================================================

/**
 * Error codes for voice status operations.
 */
export type VoiceStatusErrorCode =
  | 'INVALID_CALLSIGN'
  | 'INVALID_PHASE'
  | 'INVALID_MESSAGE'
  | 'NO_CALLSIGN'
  | 'TTS_FAILED'
  | 'TTS_TIMEOUT'
  | 'SANITIZATION_FAILED';

/**
 * Custom error class for voice status operations.
 */
export class VoiceStatusError extends Error {
  constructor(
    public readonly code: VoiceStatusErrorCode,
    message: string,
    public readonly details?: Record<string, unknown>
  ) {
    super(message);
    this.name = 'VoiceStatusError';
  }
}
