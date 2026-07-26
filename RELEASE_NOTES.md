# CodexMonitor 0.7.5

This patch makes weekly quota activation safer and ensures automatic checks run after the Mac screen or user session becomes active again.

## Reliable lifecycle checks

- Checks hourly while automatic weekly activation is enabled.
- Checks after the Mac wakes, the display wakes, or the user session becomes active.
- Coalesces closely spaced lifecycle events to avoid duplicate refreshes.
- Adds persistent logs for scheduler decisions and per-account activation results.

## Safer weekly reset detection

- Never sends an automatic activation request when weekly usage is non-zero.
- Treats a newly observed or rounded 100% value as a baseline unless a reliable reset or seven-day cycle signal exists.
- Stores a seven-day cooldown after every successful or ambiguous activation attempt.
- Prevents overlapping automatic and manual activation batches.
- Keeps manual refresh available for all authenticated Codex accounts whose weekly quota is fully available or whose weekly window is temporarily missing.
