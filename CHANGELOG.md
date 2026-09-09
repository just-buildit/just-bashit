# Changelog

## [Unreleased]

### Added

- **The `ssh` step repairs a `~/.ssh` that lost its permissions, not just the
    directory.** It set `0700` on `~/.ssh` and `0600` on a key it generated
    itself, so a directory whose contents were *synced into place* kept
    whatever modes it arrived with — and `ssh` then refuses the key with
    `UNPROTECTED PRIVATE KEY FILE` without saying how to fix it.

    `jbx setup-system -s ssh` now sweeps the whole directory. This is not a
    substitute for copying properly: `rsync -a` and `tar` both carry POSIX
    modes, so a Linux-to-Linux move loses nothing. It is for the crossings
    that have nowhere to record them — a Windows filesystem under WSL (DrvFs
    reports `0777`), FAT, a zip, or a git checkout, which keeps only the exec
    bit.

    Private keys are found by their `-----BEGIN … PRIVATE KEY-----` header
    rather than by name, so a key with no matching `.pub` is still repaired.
    `config` and `authorized_keys` are covered; `*.pub` and `known_hosts` are
    left alone.

    The sweep uses `go-rwx`, so it only ever tightens: a key deliberately at
    `0400` keeps `0400` instead of gaining owner-write, and a second run
    changes nothing. It reads first lines with the `read` builtin, so it adds
    no command to the set a PATH-restricted machine needs to reach this step.

### Changed

- **`make install-deps` runs this repo's own script instead of the published
    one.** The target fetched `install-deps.sh` from the CDN via `jbx`, while
    CI ran `src/just_bashit/install-deps.sh` — one step with two execution
    homes, in the one repo that owns the script. The version under development
    was never what ran locally, so a change could not be tried without
    releasing it first.

    `standard.mk` gained an `INSTALL_DEPS_CMD` hook upstream (defaulting to
    the existing fetch, so no other repo changes), and this repo sets it to
    the local script. CI still invokes the script directly, because the
    container jobs install `make` *from* `bootstrap.toml` and it does not
    exist yet at that point — but both callers now run the same command.

## [0.5.1] - 2026-09-08

### Added

- **`version-files-check`: a gate on the bumpversion table.** Three releases
    have now been damaged by the same class of bug — `just-runit`'s `_VERSION`
    was unregistered and sat at 0.1.4 through two releases, `make-run.sh`
    shipped in 0.4.0 with no entry, and the `jb.toml` → `bootstrap.toml`
    rename left an entry pointing at a file that no longer existed, which
    broke `make bump-version` outright. Each was found by hand, at release
    time, by someone wondering why a number was wrong.

    `version-check` cannot catch any of them: it compares the manifests to
    each other *after* a bump, so it is blind to a bump that never ran, an
    entry that quietly matched nothing, and a line it was never told about.

    The new gate checks three things — every registered `filename` exists,
    every registered `search` actually matches in its file (a search that
    matches nothing bumps *silently* and is worse than a missing entry), and
    every version-declaring **line** is covered, not merely every file. The
    line-level distinction is the whole point: `just-runit` was registered for
    its header while its `_VERSION` went unbumped, and a file-level check
    passes that green. The first draft of this gate was file-level and did
    exactly that, which is why the gate now has its own tests.

    Declarations are told from prose without an exclusion list to drift: a
    line counts only if the version is quoted, or the line matches a search
    shape already in the table. Source and docs narrate releases — `just-runit`
    itself says "This triggered on jb until 0.5.0" — and bumping those
    sentences would make them false.

    Runs in `make lint`, so it gates every PR rather than only the release.

## [0.5.0] - 2026-09-07

### Added

- **`install-deps` honours the standard proxy variables, and `--proxy URL`
    sets them.**

    Exporting `http_proxy` and running `make install-deps` appeared to be
    ignored. It was: `sudo` resets the environment, so every proxy variable
    was dropped on the far side of the escalation, and nothing the caller
    could do from their own shell would fix it.

    The assignments are now re-applied *after* the `sudo` binary rather than
    before it, surviving `env_reset` without depending on the sudoers
    `env_keep` list. Order is the whole point — `env http_proxy=… sudo   apt-get` sets the variable for `sudo` itself and has it reset away again.

    No per-manager translation was needed: apt, pacman, dnf, zypper, apk and
    brew all fetch over libcurl or read these names directly. `--proxy` sets
    `http_proxy` and `https_proxy` in both spellings, because apt, apk and
    libcurl read the lowercase names while Homebrew's Ruby reads the
    uppercase ones. `all_proxy` and `no_proxy` are only ever carried through
    from the environment: one URL says nothing about which hosts to bypass or
    how to reach a SOCKS relay, so synthesising them would be a guess.

    A `no_proxy` with no proxy beside it is left alone rather than wrapping
    every command in `env` — it describes exceptions to a configuration that
    does not exist. The variables are also exported into the script's own
    environment, so a verbatim `cmd` array inherits them without being
    rewritten.

- **`install-deps` derives whether it needs `sudo`, with `--sudo` /
    `--no-sudo` to force it.**

    The prefix was hardcoded, which made `bootstrap.toml` unusable as the
    single source of dependencies: a CI container runs as root and ships no
    `sudo` binary, so every run of the list had to be duplicated inline in
    the workflow, per distro. Both copies then drifted independently.

    A command is now prefixed only when the manager needs root, the caller is
    not already root, and `sudo` resolves on `PATH` — so the same invocation
    works on a workstation and in a root container with no flag. `brew` is
    never prefixed; Homebrew refuses to run under `sudo`. Not root and no
    `sudo` warns on stderr and runs unprivileged, letting the package manager
    report the real permission failure rather than guessing at another
    escalation tool.

    The decision is made once and read by both the executor and the
    `--dry-run` printer, so `-n` output is exactly what would have run.
    `cmd` arrays are still executed verbatim and are the one place a
    hardcoded `"sudo"` will still break a root container — the documented
    examples no longer contain one.

### Changed

- **CI installs from `bootstrap.toml` instead of repeating the package list
    per container image.** Each job now bootstraps only what
    `actions/checkout` needs — `git`, plus a TLS trust store on the images
    that ship none, plus `bash` on Alpine — and then runs `install-deps.sh`
    against the manifest. The four inline Linux lists, the macOS `brew   install` line and the coverage job's copy are gone; the dev dependency
    list now exists exactly once. Windows is the remaining carve-out:
    `msys2/setup-msys2` takes its package list as an action input, before
    checkout, so `[dev.msys2]` is still mirrored in the workflow.

- **BREAKING: `jb.toml` is now `bootstrap.toml`, and `jb` / `just-buildit` are
    no longer runner names.**

    `jb` reads as just-buildit — the PEP 517 build backend — which has never
    opened that file; it reads `pyproject.toml`, like every other backend. One
    token meant three things at once: the GitHub org, the backend, and (via a
    symlink `get-jb.sh` created) this runner.

    Naming the file after a tool was the deeper mistake, and would have been
    one without the collision: **two** different tools already read it
    (`just-runit install` takes `[tools.*]`; the package groups are read by
    `install-deps`, a separate fetched script), and the tool names were
    themselves unsettled. `bootstrap.toml` names what the file declares, which
    does not move when tools are renamed.

    Migration is `git mv jb.toml bootstrap.toml`; nothing inside changes.
    `jb.toml` and `jb-deps.toml` are still read and warn — these scripts are
    fetched live from the CDN on every CI run, so a hard cutover would break
    every repo that had not yet renamed, in the window between the publish and
    their rename. Removal is tracked separately.

- **The runner's subcommands moved to the full name.** They were only ever
    reachable under `jb` / `just-buildit`, so removing those aliases had to
    give them a home. `just-runit <subcommand>` now works and falls THROUGH to
    the SPEC runner when the first argument is not a subcommand, so
    `just-runit <url>` is unaffected. `jbx` deliberately takes no subcommands:
    that is the escape hatch that keeps a script genuinely named `install`
    reachable as `jbx install`, with no SPEC shadowed by a keyword.

    `get-jb.sh` stops creating the `jb` and `just-buildit` symlinks and prunes
    them on upgrade, alongside the existing `jr` / `jx` pruning.

### Fixed

- **`make bump-version` was broken, so no release could be cut.** The
    `jb.toml` → `bootstrap.toml` rename updated the file but not the
    `[[tool.bumpversion.files]]` entry pointing at it, so every bump died with
    `FileNotFoundError: File not found: 'jb.toml'`. Nothing caught it because
    no release had been attempted since the rename — `version-check` compares
    the manifests to each other, which cannot detect a bump that never ran.

- **`toml.sh` silently parsed a CRLF file as empty.** `read` strips the
    newline but not the carriage return, and both places that recognise a
    section header are exact matches — `[[ "$line" == "$target" ]]` in
    `toml_get_array`, and a `$`-anchored regex in `toml_discover_groups`. A
    trailing CR failed both, so every function returned success with no
    output.

    On Windows, where `actions/checkout` writes CRLF, that meant
    `install-deps` found no packages in a perfectly valid `bootstrap.toml`.
    It went unnoticed because every fixture in the suite is written with
    `printf`, so LF was the only line ending ever exercised — the bug was
    only reachable through a file that had been through a checkout, which the
    tests never used. The regression tests now build CRLF fixtures explicitly.

- **`make ship` could report a release as failed while it succeeded.**
    `release-watch` took the newest release run with `--limit 1`, but `ship`
    is `tag-release` then `release-watch`, and the tag push returns before
    GitHub has created the run — so the newest row was still the *previous*
    release. Shipping v0.4.1 watched a run that had failed the night before
    and exited 1 while the real release went on to succeed. A watcher that can
    report the wrong run is worse than no watcher, because the failure it
    invents looks exactly like a real one. It now selects the run by tag —
    `--branch "v$VERSION"`, which is what a tag-triggered run carries — and
    waits up to 60s for it to exist, erroring clearly if it never does.

- **A re-dispatched release always failed at the last step.** Since
    `gh release create` refuses an existing tag, re-driving a release that had
    already got as far as publishing died on "a release with the same tag name
    already exists" — after build and publish had both succeeded. The
    `workflow_dispatch` trigger was added to this workflow so a release could
    be re-driven through a webhook outage; a final step that cannot survive a
    second run takes that ability back. It now updates the release in place
    when one already exists.

## [0.4.1] - 2026-08-06

### Added

- **`make-run` is documented.** It shipped in 0.4.0 as the headline feature
    and appeared in no page, no nav entry, and no line of the README — so the
    one tool whose whole purpose is ending hand-transcribed commands could
    only be found by reading its source. New page under Libraries covering
    `mk-var`, `mk-vars`, `mk-run`, `mk-has` and `mk-origin`, the
    undefined-is-not-empty rule, and why the queries avoid `--eval`.

- **`docs-coverage` gate.** Two invariants, one for each way the above went
    unnoticed: every file shipped in `src/just_bashit/` must be named
    somewhere in the docs, and every page under `docs/` must be reachable
    from `zensical.toml`'s nav. `docs/changelog.md` is excluded as a mention
    source — it records every script ever added, so counting it would pass
    everything the moment it was released. Dispatched from pre-commit with
    `always_run`, so it runs inside `make lint` (which CI runs) and fires on
    commits touching no markdown, which is what adding a script looks like.

### Fixed

- **The docs pointed at `src/`, where nothing has lived since 0.2.0.**
    Scripts moved to `src/just_bashit/` for Python packaging and the docs kept
    the old path, so every `. just-bashit/src/datetime.sh` in the README, the
    getting-started guide, and all ten library pages failed for anyone who
    copied one — including from an unpacked release tarball, which carries the
    current layout.

- **The README described a package layout that no longer existed**, and never
    mentioned installation, the `jb` / `jbx` / `jb-inspect` entry points, or
    `make-run`.

## [0.4.0] - 2026-08-06

### Added

- **`make-run.sh` — ask a repo what its commands actually are.** Anything
    needing a project's command has been transcribing it by hand, and
    transcriptions drift: a skill doc said `make docs` runs
    `uv run zensical build --clean`, the sanctioned default was
    `uv run --group dev zensical build --clean --strict`, and doppler — which
    overrides `ZENSICAL` — actually runs `uv run --group docs ...`. Three
    answers, two wrong, nothing to make them disagree out loud. `mk-var`,
    `mk-vars`, `mk-run`, `mk-has` and `mk-origin` read the result of
    `standard.mk`'s defaults layered with the repo's overrides, so there is no
    second copy to vendor and nothing to keep in sync. Reachable as
    `jbx make-run` or `jbx just-bashit:make-run`.

    Two properties are pinned by tests, both so that an empty answer means
    something specific rather than nothing: an **undefined** variable is an
    error and never an empty string (`DOCS_CHECK_CMD ?=` is legitimately
    empty; a typo'd name is not), and an **unparseable** makefile fails loudly
    (`make -pRrq` exits 1 in question mode, which is normal, and 2 when it
    cannot read the makefiles at all).

### Fixed

- **CI is reachable when GitHub sheds webhooks.** `push` and `pull_request`
    are both webhook-delivered, so during the 2026-08-06 Actions incident —
    deliveries throttled to ~15% — this repo had no reachable trigger at all
    and `gh workflow run` returned 422. `workflow_dispatch` is only honoured
    when it exists on the default branch, so it could not be added from the
    branch that needed it. `ci.yml` now carries it.

- **`make-run` avoids `--eval`, which GNU make 3.81 lacks.** The option
    arrived in 3.82 and macOS still ships 3.81 as `/usr/bin/make`, so the
    first cut passed every Linux runner and failed only on macOS — confirmed
    by a real run, where exactly the `--eval` callers failed and the rest
    passed. The query now goes through a sentinel target in a throwaway
    makefile passed alongside the repo's own via `-f`.

## [0.3.2] - 2026-08-03

### Fixed

- **The bootstrap now fetches on macOS/BSD again.** `just-runit` and
    `setup-system.sh` run under a strict `IFS=$'\n\t'` (no space), then passed
    curl an *unquoted* `$(_curl_retry_opts)` of a space-joined flag string —
    which does not word-split under that IFS, so curl received the whole
    `--retry 3 --retry-connrefused --retry-all-errors` as one bogus option and
    aborted every fetch (`curl: option --retry 3 …: is unknown` → `fetch   failed`). The retry flags are now a bash array expanded
    `"${_CURL_RETRY_OPTS[@]}"`, so they split into distinct arguments regardless
    of IFS. (The EL8 path from 0.3.0 was affected identically; its test masked
    the bug by never parsing the flags.)

## [0.3.1] - 2026-08-03

### Fixed

- **The bootstrap now works on macOS/BSD, which have no `sha256sum`/`md5sum`.**
    `just-runit` hashed cache keys and verified downloads with the GNU coreutils
    names, so on macOS a fetch died with `sha256sum: command not found` and
    `jbx`/`install-deps` could not run at all. It now prefers the coreutils
    tools and falls back to `shasum -a 256` / `md5`.

## [0.3.0] - 2026-08-03

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
