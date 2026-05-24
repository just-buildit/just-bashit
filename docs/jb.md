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

### `jb help`

```
jb help
jb -h
jb --help
jb            # bare invocation also prints help
```

Prints the top-level subcommand list and exits.

---

## `jb install` *(planned)*

```
jb install
```

Read `jb.toml` in the current directory, pre-fetch every declared
`[tools.NAME]` into the cache. Intended for CI warm-up and project
on-boarding — run once, subsequent `jbx` calls are cache hits.

Not yet implemented. Track progress in the just-bashit issue tracker.

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
