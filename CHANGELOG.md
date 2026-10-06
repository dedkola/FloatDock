# Changelog

All notable changes to FloatDock are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Community health files: contributing guide, security policy, code of conduct
- Issue and pull request templates
- CI workflow building and testing on macOS 26
- Dependabot configuration for Swift packages and GitHub Actions

## [0.1.0] - 2026-10-06

Initial commit of the sampling core.

### Added

- `FloatDockCore`: a UI-free library owning all metric collection
  - `CPUProvider` — busy/user/system/idle from `host_statistics`
  - `MemoryProvider` — used/wired/compressed plus swap from `vm_statistics64`
  - `GPUProvider` — utilization from IOKit `IOAccelerator` performance statistics
  - `NetworkProvider` — up/down rates on the physical interface behind PPP/VPN layers
- `MetricReading` — per-metric validity states (`warmingUp`, `available`, `stale`,
  `unavailable`) so unreadable metrics are never shown as zero or stale values
- `MetricsSampler` — a single actor and one cancellable scheduler at 1 Hz
- `SegmentedHistory` — bounded history for charts
- `MetricMath` — overflow-safe rate and percentage arithmetic
- `FloatDockApp` — SwiftUI/AppKit shell: floating dock, tiles, history chart,
  appearance settings, menu bar item
- `--probe N` headless diagnostic mode emitting JSON snapshots
- Test suites for metric math and segmented history
- Build, run, and test scripts with shared toolchain resolution

[Unreleased]: https://github.com/dedkola/FloatDock/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/dedkola/FloatDock/releases/tag/v0.1.0
