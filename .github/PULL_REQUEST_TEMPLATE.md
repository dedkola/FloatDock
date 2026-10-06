<!--
Thanks for the pull request. A few things that make review quick:
-->

## What this changes

<!-- One or two sentences. Link the issue if there is one. -->

Fixes #

## Why

<!-- The reasoning. If it's a trade-off, say what you gave up. -->

## How it was verified

- [ ] `./scripts/test.sh` passes
- [ ] `./scripts/build.sh debug` passes
- [ ] `./scripts/build.sh release` passes

<!--
Anything you did by hand — launching the app, watching a specific metric, testing
on battery, checking a machine where a reading is unavailable? Say so here.
-->

## Checklist

- [ ] `FloatDockCore` still imports no SwiftUI/AppKit
- [ ] Unreadable metrics return `.unavailable(reason)`, not a zero or a stale value
- [ ] New behaviour in sampling/math/history has a test in `Tests/FloatDockCoreTests/`
- [ ] Commits follow Conventional Commits

## Screenshots

<!-- For UI changes: before and after. Delete this section if not applicable. -->
