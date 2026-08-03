# Changelog

## [Unreleased]

### Added

- `setup-system` tool: takes a fresh machine to a working one in one command —
    system packages (via `install-deps`), bash configuration, ssh key and agent,
    git defaults, `uv` + pre-commit, and Claude Code. Every step is idempotent
    and individually selectable with `-s` / `--skip`; `--dry-run` prints the
    whole plan without touching anything.
- `bashrc-template.sh` and `profile-template.sh`: an opinionated, cross-distro
    bash configuration. Up/down arrow history search, history hygiene, an
    ssh-agent that adopts an inherited one before starting its own, a git-aware
    prompt, probed colour aliases, and a bash-completion loader. Installed to
    `~/.config/just-bashit/` and sourced by a single line, so `~/.bashrc` stays
    the user's own file. Exports live in the POSIX-sh profile half so
    non-interactive shells see them too.
- `jb-setup-system` console entry point.

### Changed

- Adopted the org-wide `standard.mk`: the `Makefile` is now configuration only
    (feature flags, command variables, `include standard.mk`), and `make lint`
    runs the drift, help and ghost gates. `make help` is generated from `##`
    comments; `check-version` is now `version-check`; `make gates`,
    `make docs-check`, `make coverage-gate` and `make ship` are new.
- `mdformat` and its plugins moved from unpinned pre-commit
    `additional_dependencies` into `pyproject.toml`'s dev group, pinned by
    `uv.lock`; the hook dispatches to `make -s lint-mdformat` so it cannot format
    differently from `make format`. Added `mdformat-frontmatter`, without which
    mdformat rewrote `docs/index.md`'s YAML frontmatter into horizontal rules.
- CI's lint job runs `make lint` — the same gate, not a second implementation
    of it.
- `jb.toml` declares this repo's own system packages under `[dev.*]`, so
    `make install-deps` works here.

### Fixed

- The bootstrap now works on curl < 7.71 (RHEL/Oracle/Rocky/Alma 8 ship 7.61) —
    a large enterprise-LTS audience where `curl --retry-all-errors` aborted every
    fetch with "option --retry-all-errors: is unknown", so `jbx`/`install-deps`
    could not run at all. `just-runit` and `setup-system` now probe curl once and
    add `--retry-all-errors` only where it is supported, keeping `--retry` /
    `--retry-connrefused` (which already ride out throttling) everywhere else.
    Regression test shims a 7.61-style curl and asserts the fetch degrades
    instead of aborting.
- `add-line` no longer prints "Not enough arguments" and its help text on the
    normal two-argument call — the else branch fired whenever both `ENTRY` and
    `FILEPATH` were given.
- Version drift: `jb.toml` and `just-runit`'s `_VERSION` (what `jb version`
    prints) sat at 0.1.4 through two releases because neither was in
    `[[tool.bumpversion.files]]`. Both are listed now, and `make version-check`
    gates all four version strings.
- `make lint` could never pass: `trim-trailing-whitespace` and `shfmt` rewrote
    `match.sh`'s bare `[[` line in a loop, each undoing the other.
- `just-runit`: quoted the inner expansion in `${url#${_JBS_BASE}/}`
    (shellcheck SC2295), which otherwise treats the prefix as a glob pattern.

## [0.2.0] — 2026-06-20

### Added

- PyPI packaging: scripts are now installable via `pip install just-bashit` or
    `uv tool install just-bashit`, exposing `jb`, `jbx`, and `jb-inspect` as
    console entry points.
- `CHANGELOG.md` tracking releases in keep-a-changelog format.
- Standardized release process: `make setup`, `make bump-version`,
    `make release-branch`, `make tag-release` Makefile targets.
- Tag-triggered `release.yml` with CI gate, PyPI publish, and GitHub release
    with CHANGELOG notes.

## [0.1.9] — 2026-05-25

### Fixed

- `_JBS_BASE` URLs now always route through `_acquire_jbs` so sibling scripts
    co-land atomically — previously a direct URL bypass could leave the cache in
    a partially-populated state.

### Docs

- Added `llms.txt` for AI/search discoverability.

______________________________________________________________________

## [0.1.8] — 2026-05-25

### Fixed

- Added `pkg` and `toml` to `_JBS_LIBS` so the `install-deps` cache is always
    populated with its own transitive dependencies.

______________________________________________________________________

## [0.1.7] — 2026-05-24

### Added

- Windows/MSYS2 UCRT64 test job in CI.
- `make coverage` target wired to `kcov/kcov` container.

### Fixed

- Cross-platform compatibility: macOS (bash 3.2, BSD date), Alpine (BusyBox),
    Windows (MSYS2 POSIX ERE, `\n` in regex).
- `BASH_XTRACEFD` no longer clobbers kcov coverage collection.
- `bats` submodule used as fallback when system bats is not on `PATH`.

______________________________________________________________________

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

______________________________________________________________________

## [0.1.5] — 2026-05-23

### Added

- `jb cache` and `jb version` subcommands.
- `jb install` — pre-fetch tools from `jb.toml` into the local cache.
- `jb.toml` auto-discovery (falls back to `jb-deps.toml` for compatibility).

### Fixed

- `mapfile` replaced with `while-read` loop for bash 3.2 compatibility (macOS).
- Stale `_jbs_` helper names renamed to `_jb_`.
- Stale `jr` symlink removed.

______________________________________________________________________

## [0.1.4] — Initial release
