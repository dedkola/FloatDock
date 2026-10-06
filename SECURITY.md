# Security Policy

## Reporting a vulnerability

Please **do not open a public issue**. Report privately via either:

- GitHub's [private vulnerability reporting](https://github.com/dedkola/FloatDock/security/advisories/new)
  (preferred), or
- Email **maiden.tech@gmail.com** with `FloatDock security` in the subject.

Include what you did, what happened, and what you expected. A proof of concept
helps enormously. You'll get an acknowledgement as soon as possible, and credit
in the release notes if you'd like it.

## Scope

FloatDock reads local system counters and draws them on screen. It has no network
code, no accounts, no telemetry, and no update mechanism. There is no server
component and nothing to authenticate against.

The most interesting areas, if you're looking:

- **Counter parsing.** Network counters come from a binary route table
  (`NET_RT_IFLIST2`) parsed with manual byte offsets in `NetworkProvider`. Malformed
  or unexpectedly sized records are the highest-value place to probe — the parser
  retries the sizing race but should never read out of bounds.
- **Integer handling.** `MetricMath` performs rate and percentage arithmetic on
  raw counters that can wrap or reset. Overflows are handled explicitly; a case
  that isn't would be worth knowing about.
- **Denial of service.** The sampler runs at 1 Hz. Anything that lets a local
  process make it spin, leak, or hold unbounded history is in scope.
- **Sandbox escape.** The `--sandbox` build exists to test behaviour under
  App Sandbox. Any way it reaches beyond its entitlements is in scope.

## Out of scope

- Readings that are unavailable on particular hardware. GPU activity in
  particular is genuinely absent on some Macs — that's reported honestly, not a bug.
- Anything requiring an attacker who already has local code execution *and* the
  user's own privileges.
- macOS or Xcode issues themselves.

## Supported versions

This is pre-1.0 and moves fast. Only the latest commit on `master` is supported.
