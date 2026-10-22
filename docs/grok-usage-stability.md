# Grok quota stability follow-up (2026-09-23)

## Findings and reference implementations

- [CodexBar web billing fetcher](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Grok/GrokWebBillingFetcher.swift) sends a non-empty protobuf request (`00 00 00 00 02 08 00`) and accepts both framed gRPC-Web and raw protobuf. The old empty request can fail on newer deployments.
- [Orca Grok fetcher](https://github.com/stablyai/orca/blob/main/src/main/rate-limits/grok-fetcher.ts) identifies CLI requests with `X-XAI-Token-Auth: xai-grok-cli` and distinguishes credits from monthly billing.
- [gRPC-Web protocol](https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-WEB.md) encodes response status in trailing body frames, including trailer-only errors. HTTP 200 alone cannot establish success.
- An expired JWT can return HTTP 401. If no matching local `~/.grok/auth.json` credential is available, the account requires a new login or manually updated token.

## Changes

The dedicated `GrokUsageService` uses an ephemeral session without ambient cookies or redirects. It retries a transient read once, respects short `Retry-After` values, and leaves longer cooldowns to a later refresh. HTTP 401, access-denied 403, malformed data, and cancellation do not trigger repeated requests. Selected transient gRPC errors are also retried once.

Web requests use the updated non-empty request and identify errors from headers and trailers before accepting any data. Parsing validates message boundaries, varints, numeric values, and timestamp bounds. Raw protobuf and framed responses share the same field parser. A missing percentage is treated as zero only for a complete active protobuf period; historical dates cannot fabricate fresh quota.

For CLI credentials, missing JSON credits are unknown rather than 0%. The same credential can query the web billing endpoint, then the monthly billing endpoint. Monthly usage uses only `used` and `monthlyLimit` in the same server unit and is displayed as a monthly window. On-demand spending and prepaid balance never substitute for subscription quota.

Credential recovery is account-bound: browser cookies never get replaced by a local CLI token, and local CLI entries must match the rejected account. Refreshes for the same refresh token share work; an already-rotated local access token can be reused. Concurrent refresh writes preserve other local credential entries.

## Validation

Standalone probes cover billing JSON, raw/framed protobuf, explicit and implicit zero, malformed/overflowing fields, gRPC trailer errors, request headers/body, transient retries and limits, cancellation, same-credential fallbacks, and account identity matching. The app is also built as a universal arm64/x86_64 DMG.

Authenticated live quota recovery was not verified. The implementation does not manufacture or refresh credentials when no valid refresh source exists.
