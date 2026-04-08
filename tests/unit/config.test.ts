import { describe, expect, it } from 'vitest';

import { getDefaultAutomationConfig, loadConfigFile, mergeAutomationConfig } from '../../src/config.js';

describe('loadConfigFile', () => {
  it('returns no config when the default file is absent', () => {
    const loadedConfig = loadConfigFile({}, 'D:\\non-existent-voice-config-test');
    expect(loadedConfig).toEqual({});
  });

  it('throws when an explicit config path does not exist', () => {
    expect(() => loadConfigFile(
      { MCP_VOICE_CONFIG_PATH: '.\\missing.json' },
      'D:\\dev\\mcp-voice-status'
    )).toThrow(/Configured voice status config file not found/);
  });

  it('loads the checked-in config file successfully', () => {
    const loadedConfig = loadConfigFile({}, 'D:\\dev\\mcp-voice-status');
    expect(loadedConfig.path).toMatch(/voice-status\.config\.json$/);
    expect(loadedConfig.config?.speech?.defaultCallSign).toBe('Copilot');
    expect(loadedConfig.config?.automation?.callouts?.outcomeNarration).toBe(true);
    expect(loadedConfig.config?.automation?.callouts?.lowValueToolUpdates).toBe(false);
  });
});

describe('mergeAutomationConfig', () => {
  it('preserves defaults when no file config is provided', () => {
    const defaults = getDefaultAutomationConfig();
    const merged = mergeAutomationConfig(defaults);

    expect(merged).toEqual(defaults);
    expect(merged.callouts).not.toBe(defaults.callouts);
  });

  it('merges checked-in automation overrides onto the defaults', () => {
    const merged = mergeAutomationConfig(getDefaultAutomationConfig(), {
      automation: {
        enabled: false,
        callSign: 'Agent-7',
        callouts: {
          progressMilestones: false,
          outcomeNarration: false,
          lowValueToolUpdates: true,
        },
      },
    });

    expect(merged.enabled).toBe(false);
    expect(merged.callSign).toBe('Agent-7');
    expect(merged.callouts.taskStart).toBe(true);
    expect(merged.callouts.progressMilestones).toBe(false);
    expect(merged.callouts.outcomeNarration).toBe(false);
    expect(merged.callouts.lowValueToolUpdates).toBe(true);
  });
});
