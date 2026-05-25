# Changelog

## v0.1.8 — 2026-05-25

### Fixed

- **`toml.sh` / `pkg.sh` missing from cache** — `install-deps.sh` sources
  `${_SCRIPT_DIR}/toml.sh` and `${_SCRIPT_DIR}/pkg.sh` at startup, but only
  the libs listed in `_JBS_LIBS` were co-fetched by `just-runit`.  Adding
  `pkg` and `toml` to `_JBS_LIBS` ensures they are always present in the
  cache alongside the other libs.

---

## v0.1.7 — 2026-05-24

### Cross-platform CI

- Test matrix expanded to six platforms: Debian, Arch, Alpine, Fedora, macOS, and **Windows (MSYS2 UCRT64)**
- All platforms pass the full bats test suite on every push
- kcov coverage runs in the `kcov/kcov` container alongside the Debian job

### Cross-platform fixes

- `datetime.sh`: detect `gdate` (GNU date) on macOS; fall back to BSD `date`
- `format.sh`: replace `${var,,}` (bash 4+) with `tr` for macOS bash 3.2 compat
- `network.sh`: remove `timeout --preserve-status` (unsupported on BusyBox/Alpine)
- `inspect.bats`: skip glibc check on Alpine (musl libc)
- `install-deps.bats`: add `apk` and `msys2` sections to auto-detect fixture
- `logging.bats`: loosen `log-wait` timing assertion to integer-second match
- Regex patterns: remove `\n*` from ERE assertions (invalid in MSYS2 / BSD regex)
- bats submodule used as fallback when system bats is not on PATH (MSYS2)

### Coverage

- Fixed `BASH_XTRACEFD` clobbering kcov's internal named pipe — was causing
  kcov to hang indefinitely waiting for trace data that never arrived
- Use `BASH_XTRACEFD=${BASH_XTRACEFD:-2}` to preserve kcov's fd under kcov,
  fall back to stderr otherwise

---

## v0.1.6 — 2025-05-01

### New libraries

- **`toml.sh`** — pure-bash TOML reader: `toml_get`, `toml_discover_groups`, `toml_discover_tools`
- **`pkg.sh`** — package manager abstraction: `get-pkg-mgr`, `get-pkg-version`

### New CLI tools

- **`inspect`** — snapshot installed package versions; writes `jb.versions`; supports `apt`, `pacman`, `dnf`, `apk`, `brew`

### Other

- `install-deps` and `inspect` refactored to share `toml.sh` and `pkg.sh`
- 60+ new bats tests across all modules

---

## v0.1.5 — 2025-04-01

### jb CLI

- `jb` / `just-buildit` top-level dispatcher with `run`, `install`, `cache`, `version` subcommands
- `jbx` shorthand (equivalent to `jb run`)
- Version-aware installer with upgrade/reinstall reporting
- `jb install` pre-fetches tools declared in `jb.toml`
- `jb cache` — list and clear the local script cache
- Auto-discovery of `jb-deps.toml` and `jb.toml` in the working directory

### Other

- `install-deps`: bash 3.2 compatibility (macOS); replaced `mapfile` with `while read`
- Docs site launched at `https://just-buildit.github.io/just-bashit/`

---

## v0.1.4 — 2025-03-01

Initial public release. Libraries: `datetime`, `environment`, `file`, `format`,
`logging`, `match`, `network`, `path`. Templates: function template (getopts),
minimalist variant, executable script template.
