# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The version is
the repo-root `VERSION`; a bump carries its entry.

Entries begin at 1.3.19 — earlier history predates this file.

## [Unreleased]

## [1.3.23] - 2026-11-11

### Fixed

- **A release now stamps `Registry.cls`.** The class declares its own `VERSION`, the bump did not touch it, and the pack refused ("refusing to pack as 1.3.22 — Registry.cls declares 1.3.21"), as it already had at 1.3.20. A `release.toml` now lists `src/cls/ZPM/Registry.cls` as a version copy, so every bump moves it. 1.3.22 itself is published from this fix.

## [1.3.22] - 2026-11-11

### Added

- **`GET /admin/packages`**: read-only list of direct-published versions (`name`, `channel`,
  `include_deleted=1` filters; token-authed). Uplink/proxy rows are never listed.
- **`ZPM.Package.RemoveVersion(pkg, version, channel, purge, dryRun)`**: remove ONE version in ONE
  channel, soft (flag `deleted = 1`) or hard (`purge=1`, the bytes leave the registry), dry-run by
  default, and able to purge an earlier soft delete.

### Fixed

- **`DELETE /admin/packages/:pkg/:version` works on a channel-scoped registry.** It opened the row
  and called `DeletePackageVersion` without a channel, so it could not find or delete anything in
  `incubating` or `sprint`. It now requires `?channel=`, accepts `purge=1` and `dry_run=1`, and
  returns the removal report.

## [1.3.21] - 2026-11-05

### Fixed

- **`Registry.cls` carries the root VERSION again.** 1.3.20 was bumped at the repo root but the
  class still declared 1.3.19, so the coordinator refused to pack both channels ("refusing to pack
  as 1.3.20 — the class declares 1.3.19"). The class now declares 1.3.21 with this bump; the
  package content is otherwise unchanged.

## [1.3.20] - 2026-11-03

### Changed

- **Released at the current tip; no functional change.** 1.3.19 was built at its bump commit and
  then moved by this release's own CHANGELOG and issued-version ledger commits, so the coordinator
  had bound 1.3.19 to a commit the channel no longer pointed at and refused to rebuild. The package
  content is identical; this bump gives the channel a version whose commit is its tip.

## [1.3.19] - 2026-10-26

### Changed

- **1.3.19** — `Registry.cls` synced to the root VERSION; module.xml `Keywords` normalised and the registry port emitted explicitly; `PathUnderRoot` accepts a root that already ends in a separator (`PurgeDeleted` refused every directory); runtime coverage for disk streams and keyword normalisation.
