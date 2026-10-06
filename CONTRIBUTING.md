# Contributing to FloatDock

Thanks for taking a look. FloatDock is a small, focused project — the bar is
"does this make the dock more trustworthy or more pleasant to live with", not
"does this add a feature".

## Getting set up

You need macOS 26 (Tahoe), Xcode 26 / the macOS 26 SDK, and an Apple silicon Mac.

```bash
git clone https://github.com/dedkola/FloatDock.git
cd FloatDock
./scripts/test.sh     # confirm a green baseline before you change anything
./scripts/run.sh      # build and launch
```

`scripts/toolchain.sh` is sourced by both build and test and resolves the SDK.
If it can't find a macOS 26 SDK, set `FLOATDOCK_SDK_PATH` yourself.

## Before you open a pull request

1. **Run the tests.** `./scripts/test.sh` must pass. If you changed sampling,
   math, or history, add or update a test — those live in
   `Tests/FloatDockCoreTests/` and use Swift Testing (XCTest is disabled).
2. **Build both configurations.** `./scripts/build.sh debug` and
   `./scripts/build.sh release`.
3. **Keep the core pure.** `FloatDockCore` must not import SwiftUI or AppKit, and
   must not depend on anything in `FloatDockApp`. It's the testable half; that
   separation is the point.
4. **Respect the reading contract.** If a metric can't be read, return
   `.unavailable(reason)` with a human sentence — never a zero, and never a stale
   value dressed up as current. See `MetricReading` in `MetricModels.swift`.

## Code style

- Swift 6 language mode with strict concurrency. Everything crossing a boundary
  must be `Sendable`; prefer `actor` isolation over locks.
- Prefer explicit types over inference in public signatures.
- No new dependencies unless there's a very good reason — the app currently
  builds against the SDK alone.
- Match the surrounding style. The codebase favours small, single-purpose types
  with doc comments that explain *why*, not *what*.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/) — `feat:`, `fix:`,
`chore:`, `docs:`, `refactor:`, `test:`. Keep the subject under ~72 characters
and explain the reasoning in the body when it isn't obvious.

## Reporting bugs

Use the bug report template. The **most useful thing you can include** is the
output of the headless probe on the machine where it went wrong:

```bash
./build/FloatDock.app/Contents/MacOS/FloatDock --probe 4
```

That gives exact readings and their states, which usually identifies the problem
immediately. Please also include your macOS version and Mac model — several
readings are hardware-dependent and legitimately unavailable on some machines.

## Security

Don't open a public issue for anything security-related — see
[SECURITY.md](SECURITY.md).

## License

By contributing you agree your work is licensed under the [MIT License](LICENSE).
