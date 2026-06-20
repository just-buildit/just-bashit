# Changelog

## [Unreleased]

## [0.1.9] — 2026-05-25

### Fixed

- `_JBS_BASE` URLs now always route through `_acquire_jbs` so sibling scripts
  co-land atomically — previously a direct URL bypass could leave the cache in
  a partially-populated state.

### Docs

- Added `llms.txt` for AI/search discoverability.

---

## [0.1.8] — 2026-05-25

### Fixed

- Added `pkg` and `toml` to `_JBS_LIBS` so the `install-deps` cache is always
  populated with its own transitive dependencies.

---

## [0.1.7] — 2026-05-24

### Added

- Windows/MSYS2 UCRT64 test job in CI.
- `make coverage` target wired to `kcov/kcov` container.

### Fixed

- Cross-platform compatibility: macOS (bash 3.2, BSD date), Alpine (BusyBox),
  Windows (MSYS2 POSIX ERE, `\n` in regex).
- `BASH_XTRACEFD` no longer clobbers kcov coverage collection.
- `bats` submodule used as fallback when system bats is not on `PATH`.

---

## [0.1.6] — 2026-05-24

### Added

- `toml.sh` and `pkg.sh` extracted as first-class library modules.
- `inspect` tool: shows resolved tool sources, cache state, and dependency
  graph without executing anything.
- `install-deps` overhauled: better defaults, escape-hatch command override,
  32+ new bats tests raising coverage above 40 %.

### Changed

- CI matrix extended to Debian, Arch, Fedora, Alpine.
- Test suite expanded to 24+ additional tests across all modules.

---

## [0.1.5] — 2026-05-23

### Added

- `jb cache` and `jb version` subcommands.
- `jb install` — pre-fetch tools from `jb.toml` into the local cache.
- `jb.toml` auto-discovery (falls back to `jb-deps.toml` for compatibility).

### Fixed

- `mapfile` replaced with `while-read` loop for bash 3.2 compatibility (macOS).
- Stale `_jbs_` helper names renamed to `_jb_`.
- Stale `jr` symlink removed.

---

## [0.1.4] — Initial release
