# Agent Instructions

## Voice Status

You have access to voice status tools. Use them to keep the user informed:

1. Before using voice status, check `voice-status.config.json` in the repo root if it exists and honor its `automation` settings.
2. At the start of a meaningful task, call `register_callsign` with the configured call sign (default: `"Copilot"`).
3. Use `speak_status` only for contextual callouts that help the user follow progress and outcome:
   - `confirm` when you start a meaningful task or hit a real milestone
   - `waiting` when you need user input
   - `blocked` when an external dependency or constraint is stopping progress
   - `done` when the task is complete; when there is a concrete result or answer, prefer speaking that concise result summary in the `done` callout instead of only saying the task is complete
   - `error` when something fails
4. Do **not** narrate every tool call, file read, or minor step unless the config explicitly allows low-value tool updates.
5. When completion and outcome narration are enabled, successful tasks should end with a `done` callout. Use a generic completion line only if the actual result cannot be stated clearly within the message limit.
6. Keep callouts factual, brief, and timely. Prefer silence over noisy commentary.

Keep spoken messages brief and under 200 characters.
