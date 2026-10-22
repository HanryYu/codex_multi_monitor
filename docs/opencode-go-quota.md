# OpenCode Go quota integration

Researched on 2026-09-22 before implementation.

## Authoritative sources

- [Current Go limits](https://opencode.ai/docs/go/#usage-limits): the monthly dollar allowance varies by model. The rolling 5-hour and weekly allowances correspond to 20% and 50% of the monthly allowance.
- [Official usage API](https://github.com/anomalyco/opencode/blob/fe3f3a41f79ad292cc3c7c629567385a20ec5130/packages/console/app/src/routes/zen/go/v1/usage.ts): `GET /zen/go/v1/usage` accepts an API key in `Authorization: Bearer …`. It returns `usage.rolling`, `usage.weekly`, and `usage.monthly`, each containing `status`, `percent`, and an ISO-8601 `resetsAt`. A read-only, unauthenticated production probe returned HTTP 401 with `Missing API key.`; authenticated account data was not used during development.
- [Dashboard query](https://github.com/anomalyco/opencode/blob/fe3f3a41f79ad292cc3c7c629567385a20ec5130/packages/console/app/src/routes/workspace/%5Bid%5D/go/lite-section.tsx): the three windows include weighted `usage`, `limit`, `status`, `usagePercent`, and `resetInSec`. Usage and limit share the same microcent unit. The detail query distinguishes actual model cost from weighted quota cost.
- [Dashboard percentage calculation](https://github.com/anomalyco/opencode/blob/fe3f3a41f79ad292cc3c7c629567385a20ec5130/packages/console/app/src/lib/lite-usage.ts): `usage / limit * 100`, rounded to one decimal. Model-equivalent allowance is `limit / multiplier`.
- [Server window calculation](https://github.com/anomalyco/opencode/blob/fe3f3a41f79ad292cc3c7c629567385a20ec5130/packages/console/core/src/subscription.ts): server status distinguishes exhausted quota from a rounded display percentage; reset times are calculated on the server, including subscription-relative monthly boundaries.

## Implementation decisions

1. Accept manually supplied API keys through the existing account credential field. API keys use the official JSON endpoint and do not require a Workspace ID. Cookie accounts use Console JSON first, with a legacy dashboard fallback when a legacy auth cookie is present.
2. Use the server's weighted consumption, percentages, status, and reset timestamps. Do not hard-code model prices, promotional multipliers, or calculate subscription usage from local token history. For example, a $1 cost charged at a 4x quota multiplier consumes 4/12 of the $12 base rolling allowance, not 1/12; the server has already applied that multiplier.
3. Keep the shared app's integer percentage representation. Floor non-exhausted percentages and cap them at 99; only an exhausted window reaches 100. This prevents 99.9% or a dashboard-rounded 100.0% with status `ok` from generating a false exhausted state.
4. Retain the credential/workspace-bound, 30-minute server-result cache with its visible Cached label. Auto-discovery binds the cache to the actual returned Workspace ID and must confirm that workspace before falling back. A window reset invalidates the snapshot; a failed refresh cannot infer the new window's usage. Bump the cache schema so old rounding results are not reused.
5. Preserve the existing same-host HTTPS redirect guard for both Cookie and Authorization headers. Never retrieve credentials from browsers or local CLI storage automatically.

## Validation

The standalone probe covers old/new dashboard payloads, API JSON and timestamp formats, all three windows, model-weighted usage, near-limit rounding, malformed/nested/null fields, API-key/Cookie request routing, and credential/workspace cache isolation. Network routing tests use synthetic credentials and URLProtocol responses.

```sh
swiftc -module-cache-path /tmp/codex-monitor-module-cache \
  Sources/CodexMonitor/Models/UsageResponse.swift \
  Sources/CodexMonitor/Services/OpenCodeGoUsageService.swift \
  scripts/test_opencode_go_usage.swift -o /tmp/test_opencode_go_usage
/tmp/test_opencode_go_usage
```

On the development machine, the default macOS 27 Command Line Tools SDK lacks
the SwiftUI macro plugin. The local preview was built with the installed macOS
26.5 SDK instead:

```sh
SWIFT_BUILD_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
  bash scripts/build-dmg.sh 0.7.12-settings-go-preview
```

The packaging script keeps native SwiftPM architecture paths and verifies each
architecture separately for compatibility with the current Command Line Tools.
The preview is ad-hoc signed for local testing, not notarized for distribution.


## Console migration follow-up (2026-09-23)

The previous implementation missed the migrated Console contract. Research compared
[CodexBar's fetcher](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/OpenCodeGo/OpenCodeGoUsageFetcher.swift),
[its migration fixtures](https://github.com/steipete/CodexBar/blob/main/Tests/CodexBarTests/OpenCodeGoConsoleMigrationTests.swift),
and [Orca's migration](https://github.com/stablyai/orca/pull/21462).

- Preserve `__Host-console_session` in the credential cookie allowlist. The old
  `auth` cookie and the new Console session are distinct.
- Discover workspaces using `GET /console/api/orgs`; request
  `GET /console/api/go/status` with `x-org-id` and a Console Referer.
- Parse `access.meters.fiveHour`, `week`, and `month`. Percent is
  `usedMicroCents / limitMicroCents * 100`; money may be a JSON string or number.
  Missing rolling reset timestamps remain unknown; a missing monthly timestamp
  uses `access.endsAt`. No locally inferred reset or consumption is substituted.
- A valid response with `access: null` means no Go subscription in that workspace.
  Discovery tries the other accessible workspaces before reporting failure.
- Legacy auth can still use the old server-function discovery and SSR quota page
  if Console is unavailable. Console-only sessions do not depend on legacy routes.
- Explicit unauthorized/no-subscription responses invalidate the matching cached
  result; another workspace failure cannot revive it.
- An expired legacy `auth` cookie may return HTTP 401 from Console discovery or
  redirect the legacy quota page to login. The app asks for a fresh Console
  session in that case; authenticated live recovery was not verified.

Regression coverage includes migrated request routing, session-cookie filtering,
organization IDs and Console URLs, numeric/string meter amounts, unknown reset
handling, billing-period monthly resets, no-subscription workspaces, legacy
fallback, and credential/workspace cache isolation.
