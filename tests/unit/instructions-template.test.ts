import { readFileSync } from 'fs';
import { resolve } from 'path';

import { describe, expect, it } from 'vitest';

const repoRoot = resolve(process.cwd());

function readRepoFile(relativePath: string): string {
  return readFileSync(resolve(repoRoot, relativePath), 'utf8');
}

describe('voice status instruction templates', () => {
  it('keep checked-in instructions and installer template aligned on outcome narration', () => {
    const checkedInInstructions = readRepoFile('.github\\copilot-instructions.md');
    const installerScript = readRepoFile('scripts\\Install-VoiceStatusClientConfig.ps1');

    const expectedLines = [
      'Use `speak_status` only for contextual callouts that help the user follow progress and outcome:',
      '- `done` when the task is complete; when there is a concrete result or answer, prefer speaking that concise result summary in the `done` callout instead of only saying the task is complete',
      'When completion and outcome narration are enabled, successful tasks should end with a `done` callout. Use a generic completion line only if the actual result cannot be stated clearly within the message limit.',
    ];

    for (const line of expectedLines) {
      expect(checkedInInstructions).toContain(line);
      expect(installerScript).toContain(line);
    }
  });
});
