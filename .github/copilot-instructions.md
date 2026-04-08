# Agent Instructions

## Voice Status

You have access to voice status tools. Use them to keep the user informed:

1. At the start of any task, call `register_callsign` with "Copilot"
2. Use `speak_status` to announce:
   - `confirm` when you start a task
   - `waiting` when you need user input
   - `done` when you complete a task
   - `error` when something fails

Keep spoken messages brief and under 200 characters.
