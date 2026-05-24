# jb

`jb` is the top-level CLI for the just-buildit toolchain. It dispatches to
subcommands; the first and most-used is `run`.

```
jb <command> [OPTIONS] [ARGS...]
```

---

## Names and aliases

The installer creates three names in `~/.local/bin`:

| Name | Type | Purpose |
|---|---|---|
| `just-buildit` | binary | canonical name — always installed, never conflicts |
| `jb` | symlink | short alias — skipped if already taken by another tool |
| `jbx` | symlink | shorthand for `jb run` — always installed |

`jbx SPEC …` and `jb run SPEC …` are identical. Use whichever fits the
context: `jbx` for one-liners, `jb run` in scripts for clarity.

If `jb` is already installed by a different tool on your system, the installer
warns and skips the symlink. Use `just-buildit` in that case — it is always
available and unique.

---

## Subcommands

### `jb run` — ephemeral tool runner

```
jb run [OPTIONS] SPEC [FUNCTION [ARGS...]]
```

Alias: `jbx`. Resolve `SPEC` to a script, optionally call `FUNCTION`, then
discard. See [just-runit.md](just-runit.md) for the full reference:
SPEC forms, option flags, cache management, recipes.

### `jb version`

```
jb version
jb -V
jb --version
```

Prints `jb vX.Y.Z` and exits.

### `jb cache` — cache management

```
jb cache clear           # remove everything under ~/.cache/just-runit/
jb cache clear jbs       # remove the just-bashit co-fetch bundle only
jb cache clear <url>     # remove the entry for one specific URL
jb cache -h              # show cache subcommand help
```

See [just-runit.md — Cache](just-runit.md#cache) for a full description of
the cache layout and when to use each form.

### `jb help`

```
jb help
jb -h
jb --help
jb            # bare invocation also prints help
```

Prints the top-level subcommand list and exits.

---

## `jb install`

```
jb install
```

Walk up from the current directory to find `jb.toml`, then pre-fetch every
`source` declared under `[tools.*]` into the local cache. Subsequent `jbx`
calls for those tools are instant cache hits.

```
  reading /path/to/project/jb.toml
  -> just-bashit:install-deps ok
  -> just-bashit:just-makeit ok
  2 fetched
```

Intended for CI warm-up and first-run onboarding. Run it once after cloning;
`jbx` will stay offline after that until the TTL expires.

---

## `jb.toml` — project tool declarations

Projects declare their `jbx` dependencies in a `jb.toml` at the repo root.
`jb install` (once shipped) reads this to pre-fetch tools; `jbx` will
consult it before falling through to `aliases.toml`.

```toml
[project]
name    = "my_project"
version = "0.1.0"

[tools.install-deps]
source    = "just-bashit:install-deps"
deps_file = "jb-deps.toml"
groups    = ["runtime", "dev"]

[tools.just-makeit]
source = "just-bashit:just-makeit"
config = "just-makeit.toml"
```

---

## Upgrade

```bash
. <(curl -sSL https://just-buildit.github.io/get-jb.sh)
```

The installer is version-aware: it compares `_VERSION` in the installed binary
against the upstream and reports `already at vX.Y.Z`, `upgrading`, or
`reinstalling`. To force reinstall regardless:

```bash
JB_REINSTALL=1 . <(curl -sSL https://just-buildit.github.io/get-jb.sh)
```
