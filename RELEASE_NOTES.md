# CodexMonitor 0.7.0

This release expands CodexMonitor from a Codex-only quota utility into a multi-provider menu bar monitor for **Codex, Claude, and Grok**.

## Claude monitoring

- Automatically imports Claude OAuth credentials from the macOS Keychain entry `Claude Code-credentials`, with `~/.claude/.credentials.json` as a fallback.
- Refreshes expired Claude OAuth access tokens and writes rotated access/refresh tokens back to the original credential store.
- Displays the Claude 5-hour and 7-day usage windows with reset times.
- Supports manual Bearer tokens, complete `Authorization` headers, and Claude auth JSON.

## Grok monitoring

- Automatically imports Grok credentials from `~/.grok/auth.json`.
- Refreshes expired Grok OIDC credentials and writes them back atomically.
- Reads Grok CLI billing usage, including the current weekly period and reset time.
- Supports the shared weekly quota shown on grok.com through the `GetGrokCreditsConfig` gRPC-Web endpoint.
- Adds a tested Protobuf decoder for Grok web usage responses.
- Supports manual Grok Bearer tokens, local auth JSON, and complete browser Cookie headers.

## Interface improvements

- Adds provider-specific official icons for Codex, Claude, and Grok.
- Shortens provider names to **Claude** and **Grok** to keep account headers on one line.
- Makes the add/edit account title, labels, placeholders, credential hints, and icon respond to the selected provider.
- Adds localized provider form copy for English, Japanese, Simplified Chinese, and Traditional Chinese.
- Preserves provider information through account backup and iCloud sync.

## Fixes

- Fixes Grok billing decoding for the current `{ "config": { ... } }` response envelope.
- Keeps compatibility with the earlier unwrapped Grok response shape.
- Separates provider authentication and usage fetching so a Claude or Grok failure does not break Codex accounts.

## Security note

Access tokens and browser cookies grant account access. CodexMonitor stores imported credentials using its encrypted local token storage. Do not share credentials or include them in bug reports.
