/**
 * Windows Text-to-Speech wrapper using PowerShell and System.Speech.
 * 
 * Spawns a PowerShell process with System.Speech.Synthesis to speak text.
 * Uses execFile with argument array to prevent shell injection.
 */

import { execFile } from 'child_process';
import { promisify } from 'util';
import { TTSConfig, VoiceStatusError } from '../types.js';

const execFileAsync = promisify(execFile);

/** Default TTS configuration */
const DEFAULT_TTS_CONFIG: TTSConfig = {
  timeoutMs: 30000,
  rate: 0,
  volume: 100,
};

/**
 * Speak text using Windows TTS via PowerShell.
 * 
 * @param text - Pre-sanitized text to speak (must already be sanitized!)
 * @param config - TTS configuration options
 * @throws VoiceStatusError if TTS fails or times out
 */
export async function speakText(
  text: string,
  config: Partial<TTSConfig> = {}
): Promise<void> {
  const { timeoutMs, rate, volume } = { ...DEFAULT_TTS_CONFIG, ...config };

  if (!text || text.trim().length === 0) {
    throw new VoiceStatusError('TTS_FAILED', 'Cannot speak empty text');
  }

  // Build PowerShell script
  // Text is expected to be pre-sanitized with single quotes escaped
  const psScript = `
Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$synth.SetOutputToDefaultAudioDevice()
$synth.Rate = ${rate}
$synth.Volume = ${volume}
$synth.Speak('${text}')
$synth.Dispose()
`.trim();

  try {
    await execFileAsync(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        psScript,
      ],
      {
        timeout: timeoutMs,
        windowsHide: true,
      }
    );
  } catch (error) {
    const err = error as NodeJS.ErrnoException & { killed?: boolean };

    if (err.killed) {
      throw new VoiceStatusError(
        'TTS_TIMEOUT',
        `TTS operation timed out after ${timeoutMs}ms`,
        { timeoutMs }
      );
    }

    throw new VoiceStatusError(
      'TTS_FAILED',
      `TTS failed: ${err.message}`,
      { originalError: err.message, code: err.code }
    );
  }
}

/**
 * Check if Windows TTS is available.
 * Attempts to load the System.Speech assembly without speaking.
 * 
 * @returns true if TTS is available, false otherwise
 */
export async function isTTSAvailable(): Promise<boolean> {
  const psScript = `
Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$synth.Dispose()
Write-Output "OK"
`.trim();

  try {
    const { stdout } = await execFileAsync(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        psScript,
      ],
      {
        timeout: 5000,
        windowsHide: true,
      }
    );

    return stdout.trim() === 'OK';
  } catch {
    return false;
  }
}
