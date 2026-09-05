# CodexMonitor 0.7.11

This release improves quota planning, account credential reliability, and five-hour refresh behavior across Codex, Claude, Grok, and OpenCode Go.

## Weekly quota planning

- Shows the remaining weekly allowance as an approximate number of complete 5-hour allowances directly inside the weekly quota card.
- Uses OpenCode Go's published `$30 weekly / $12 per 5 hours = 2.5x` capacity ratio.
- Starts Codex and Claude with provider-aware full-window baselines, then refines the ratio from each account's paired 5-hour and weekly usage changes.
- Keeps the conversion independent of the current 5-hour remaining percentage, so a fresh 100% 5-hour window does not change the weekly estimate.
- Adds a Display setting to hide the compact conversion hint.

## Account and credential reliability

- Refreshes expiring Codex credentials from saved, active, or app-managed auth sources while preserving the newest matching full auth bundle.
- Adds explicit reconnect actions for Codex and Grok accounts and clearer authentication-expired versus upstream-format errors.
- Prevents an older switched `auth.json` from replacing a newer saved credential bundle.
- Adds account reordering, hide/show controls, safer deletion confirmation, and persistent ordering through iCloud sync and backups.

## Five-hour quota refresh

- Starts and stops the scheduler with the setting instead of leaving its timer active while disabled.
- Records a scheduled refresh only after the minimal Codex request succeeds, then refreshes displayed usage immediately.
- Prevents overlapping attempts, retries transient failures within the scheduled window, and reports actionable failure reasons.
- Makes wake-schedule enablement and cleanup transactional, including recovery from legacy leftover schedules.

## Grok usage compatibility

- Supports legacy and unified Grok billing responses without deriving subscription quota from on-demand currency fields.
- Uses the installed Grok client version when requesting billing data and distinguishes authentication failures from upstream response changes.
- Preserves valid zero-usage responses at the start of a new billing period.

## Validation

- Adds focused regression coverage for Codex auth bundle selection, Grok billing and web usage decoding, five-hour refresh controls, and weekly-to-5-hour quota conversion.
- Continues validating OpenCode Go dashboard parsing, weekly activation policy, relative reset times, Reset Observatory data, and semantic release ordering.
