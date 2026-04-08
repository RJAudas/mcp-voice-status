import { existsSync, readFileSync } from 'fs';
import { resolve } from 'path';
import { z } from 'zod';

import {
  AutomationConfig,
  DEFAULT_AUTOMATION_CONFIG,
  MIN_RATE_LIMIT_MS,
  VoiceStatusConfigFile,
} from './types.js';
import { callSignSchema } from './validation/schemas.js';

export const DEFAULT_CONFIG_FILE_NAME = 'voice-status.config.json';

const voiceStatusConfigFileSchema = z.object({
  speech: z.object({
    defaultCallSign: callSignSchema.optional(),
    rateLimitMs: z.number().int().min(MIN_RATE_LIMIT_MS).optional(),
    dedupWindowMs: z.number().int().min(0).optional(),
    timeoutMs: z.number().int().min(1000).optional(),
    rate: z.number().int().min(-10).max(10).optional(),
    volume: z.number().int().min(0).max(100).optional(),
  }).partial().optional(),
  automation: z.object({
    enabled: z.boolean().optional(),
    mode: z.literal('instructions').optional(),
    callSign: callSignSchema.optional(),
    callouts: z.object({
      taskStart: z.boolean().optional(),
      progressMilestones: z.boolean().optional(),
      waiting: z.boolean().optional(),
      completion: z.boolean().optional(),
      outcomeNarration: z.boolean().optional(),
      errors: z.boolean().optional(),
      lowValueToolUpdates: z.boolean().optional(),
    }).partial().optional(),
  }).partial().optional(),
}).strict();

export interface LoadedConfigFile {
  path?: string;
  config?: VoiceStatusConfigFile;
}

export function getDefaultAutomationConfig(): AutomationConfig {
  return {
    ...DEFAULT_AUTOMATION_CONFIG,
    callouts: { ...DEFAULT_AUTOMATION_CONFIG.callouts },
  };
}

export function mergeAutomationConfig(
  baseConfig: AutomationConfig,
  fileConfig?: VoiceStatusConfigFile
): AutomationConfig {
  if (!fileConfig?.automation) {
    return {
      ...baseConfig,
      callouts: { ...baseConfig.callouts },
    };
  }

  return {
    ...baseConfig,
    ...fileConfig.automation,
    callSign: fileConfig.automation.callSign ?? baseConfig.callSign,
    callouts: {
      ...baseConfig.callouts,
      ...fileConfig.automation.callouts,
    },
  };
}

export function loadConfigFile(
  env: NodeJS.ProcessEnv = process.env,
  cwd: string = process.cwd()
): LoadedConfigFile {
  const explicitPath = env['MCP_VOICE_CONFIG_PATH'];
  const configPath = explicitPath
    ? resolve(cwd, explicitPath)
    : resolve(cwd, DEFAULT_CONFIG_FILE_NAME);

  if (!existsSync(configPath)) {
    if (explicitPath) {
      throw new Error(`Configured voice status config file not found at '${configPath}'.`);
    }

    return {};
  }

  const rawText = readFileSync(configPath, 'utf8');

  let rawConfig: unknown;
  try {
    rawConfig = JSON.parse(rawText);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    throw new Error(`Invalid JSON in voice status config '${configPath}': ${errorMessage}`);
  }

  const parsedConfig = voiceStatusConfigFileSchema.safeParse(rawConfig);
  if (!parsedConfig.success) {
    const issue = parsedConfig.error.errors[0];
    const issuePath = issue?.path.length ? issue.path.join('.') : 'root';
    throw new Error(
      `Invalid voice status config '${configPath}' at '${issuePath}': ${issue?.message ?? 'Unknown error'}`
    );
  }

  return {
    path: configPath,
    config: parsedConfig.data,
  };
}
