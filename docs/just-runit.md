# just-runit

`just-runit` (alias: `jbx`) is an ephemeral bash tool runner. Fetch a script from a
URL or namespace, call a function it defines, then discard — no installation, no leftover
environment pollution. The bash equivalent of `uvx`, for anything reachable over HTTPS.

!!! danger "You are responsible for what you run"

    `jbx` fetches and executes arbitrary code from any URL you provide.
    It performs no review, scanning, or sandboxing of remote scripts.
    There is no safety guarantee of any kind — that responsibility
    belongs entirely to you. Always inspect a script before running it.

```bash
jbx just-bashit:datetime iso-8601-basic -m
# 20260522T174523.841Z
```

______________________________________________________________________

## Getting just-runit

Source the install script — it downloads `just-runit`, creates `jb`, `jbx`, and
`just-buildit` symlinks in `~/.local/bin`, and exports the updated `PATH` into your
current shell immediately (no new terminal needed):

```bash
. <(curl -sSL https://just-buildit.github.io/get-jb.sh)
```

That's it. `jb` and `jbx` are live in the shell you ran that in.

!!! warning "Use at your own risk"

    This script is provided as-is, without warranty of any kind. It writes
    to `~/.local/bin` and may modify `~/.bashrc`. The tool it installs
    runs arbitrary remote code with no safety guarantees — you are solely
    responsible for what you choose to run with it. Review the source before
    running: [get-jb.sh](https://just-buildit.github.io/get-jb.sh)

!!! note "Why source instead of pipe to bash?"

    `. <(...)` runs the script in the current shell process, so
    `export PATH=...` reaches you directly. `bash <(...)` or
    `curl ... | bash` spawn a subshell — PATH changes die with it.

To force reinstall even when already at the current version:

```bash
JB_REINSTALL=1 . <(curl -sSL https://just-buildit.github.io/get-jb.sh)
```

______________________________________________________________________

## How it works

```
jb run [OPTIONS] SPEC [FUNCTION [ARGS...]]
   or: jbx [OPTIONS] SPEC [FUNCTION [ARGS...]]
```

`jbx` resolves `SPEC` to a script URL, fetches it, sources it into a subshell,
optionally calls `FUNCTION` with `ARGS`, then exits. The subshell boundary is
the isolation — nothing leaks back to the calling shell.

Fetched scripts are cached at `${XDG_CACHE_HOME:-$HOME/.cache}/just-runit/` and
reused on subsequent calls until the TTL expires (default 1 hour).

______________________________________________________________________

## SPEC forms

| Form                    | Example                       | Resolves to                                                                       |
| ----------------------- | ----------------------------- | --------------------------------------------------------------------------------- |
| `NAME`                  | `install-deps`                | default namespace (`just-buildit.github.io`) via `aliases.toml` then direct probe |
| `NS:NAME`               | `just-bashit:logging`         | namespace `NS` — built-in: `just-buildit`, `just-bashit`                          |
| `gh:USER/REPO/PATH`     | `gh:user/repo/tool.sh`        | GitHub raw content, default branch `main`                                         |
| `gh:USER/REPO/PATH@REF` | `gh:user/repo/tool.sh@v2.1.0` | GitHub raw content at a specific ref/tag/SHA                                      |
| `https://...`           | `https://example.com/tool.sh` | Any HTTPS URL                                                                     |

**Resolution order for `NAME` / `NS:NAME`:**

1. Look up `NAME` in the namespace's `aliases.toml` (cached)
1. Probe `NS_BASE/NAME.sh` then `NS_BASE/NAME.py`
1. Error if neither resolves

```bash
# Default namespace (just-buildit.github.io)
jbx install-deps -s apt

# Explicit just-bashit namespace
jbx just-bashit:logging log -t SUCCESS "deployed"

# GitHub shorthand, pinned to a tag
jbx gh:user/repo/scripts/deploy.sh@v1.4.0 run --env prod

# Full URL
jbx https://example.com/tools/setup.sh configure
```

!!! note "just-bashit namespace co-fetch"

    Libraries like `logging` and `network` depend on other just-bashit
    libraries. When you use `just-bashit:NAME`, `jbx` co-fetches the entire `src/`
    directory into a single cache folder so relative inter-source calls
    resolve correctly — you don't have to manage this yourself.

______________________________________________________________________

## Options

| Flag      | Description                                                 |
| --------- | ----------------------------------------------------------- |
| `-l`      | List functions the script defines, then exit                |
| `-r`      | Refresh — re-fetch even if the cache is fresh               |
| `-n`      | No-cache — fetch once and discard (nothing written to disk) |
| `-c`      | Clean environment (minimal env, like `sudo` without `-E`)   |
| `-p VARS` | Comma-separated vars to pass through when using `-c`        |
| `-t TTL`  | Cache TTL in seconds. Default `3600`. `0` = keep forever    |
| `-k HASH` | Verify before running: `sha256:HASH` or `md5:HASH`          |
| `-v`      | Verbose — prints fetch/cache activity to stderr             |

______________________________________________________________________

## Cache

Scripts are cached at `${XDG_CACHE_HOME:-$HOME/.cache}/just-runit/` and shared
across all projects on the machine.

**Layout**

```
~/.cache/just-runit/
  <sha256>.sh          # cached script (key = SHA-256 of URL)
  <sha256>.meta        # sidecar: ts=<unix epoch>  url=<original URL>
  aliases-<sha256>.toml  # cached aliases.toml per namespace
  jbs/                 # just-bashit co-fetch bundle
    logging.sh
    network.sh
    ...
```

The key is a SHA-256 of the full URL, so two different URLs that happen to
return the same content get separate entries.

**TTL**

Default TTL is 3600 s (1 hour). Override per-invocation with `-t SECONDS`.
`-t 0` disables expiry — the entry is kept until manually removed or `-r` is
used.

**Inspect a cached entry**

```bash
# See which URL a cache file came from and when it was fetched
cat ~/.cache/just-runit/<sha256>.meta
# ts=1779583354
# url=https://raw.githubusercontent.com/just-buildit/just-bashit/main/src/just_bashit/install-deps.sh
```

**Force a fresh fetch (keep the entry, overwrite it)**

```bash
jbx -r just-bashit:install-deps --dry-run
```

**Fetch once, write nothing to disk**

```bash
jbx -n https://example.com/tool.sh run
```

**Purge a single entry**

```bash
jb cache clear https://raw.githubusercontent.com/just-buildit/just-bashit/main/src/just_bashit/install-deps.sh
```

Or manually — find the hash with `-v` then remove the pair:

```bash
jbx -v install-deps 2>&1 | grep 'cache hit'
# jbx: cache hit: /home/you/.cache/just-runit/1f6227a...sh

rm ~/.cache/just-runit/1f6227a...{sh,meta}
```

**Purge the just-bashit bundle** (re-fetched as a unit on next use)

```bash
jb cache clear jbs
```

**Purge everything**

```bash
jb cache clear
```

______________________________________________________________________

## Recipes

**Discover what a script exposes before calling it:**

```bash
jbx -l just-bashit:logging
# color-echo
# is-number
# iso-8601-basic
# log
# log-wait
# trim-from
```

**Pin to a checksum for auditable CI use:**

```bash
jbx -k sha256:abc123def456 https://infra.example.com/bootstrap.sh setup
```

**Clean environment — script sees only HOME, TERM, PATH:**

```bash
jbx -c https://example.com/tool.sh run
```

**Pass specific vars into a clean environment:**

```bash
jbx -c -p DEPLOY_TOKEN,AWS_REGION https://example.com/deploy.sh run
```

**Force a fresh fetch (e.g. after a release):**

```bash
jbx -r just-bashit:logging log "refreshed"
```

**Skip the cache entirely — nothing touches disk:**

```bash
jbx -n https://example.com/ephemeral.sh do-thing
```

**Script mode — no function name, just source and run:**

```bash
jbx https://example.com/setup.sh   # runs whatever the script does top-level
```

**One-liner in CI:**

```bash
jbx just-bashit:network test-internet-access -vt 10 || exit 1
```

______________________________________________________________________

## Names

The installer creates two names in `~/.local/bin`:

| Name         | Type    | Takes subcommands? |
| ------------ | ------- | ------------------ |
| `just-runit` | binary  | yes                |
| `jbx`        | symlink | **no**             |

The difference is deliberate. `just-runit` accepts the subcommands below and
falls through to the SPEC runner when the first argument is not one of them;
`jbx` never treats an argument as a subcommand. So a script genuinely named
`install` or `cache` is always reachable as `jbx install` — no SPEC is
shadowed by a keyword.

!!! note "`jb` and `just-buildit` are not runner names"

    They were until 0.5.0, which put one token on three different things: the
    GitHub org, the [just-buildit](https://github.com/just-buildit/just-buildit)
    PEP 517 build backend, and this runner. The backend keeps the name — it is
    the one that actually builds. The installer prunes both aliases on upgrade.

______________________________________________________________________

## Subcommands

These are available under `just-runit` only.

### `just-runit install`

Walk up from the current directory to find `bootstrap.toml`, then pre-fetch
every `source` declared under `[tools.*]` into the local cache. Subsequent
`jbx` calls for those tools are instant cache hits.

```
  reading /path/to/project/bootstrap.toml
  -> just-bashit:install-deps ok
```

`jb.toml` is still read, and warns. See
[bootstrap.toml](bootstrap-toml.md).

### `just-runit cache`

```
just-runit cache clear           # remove everything under ~/.cache/just-runit/
just-runit cache clear jbs       # remove the just-bashit co-fetch bundle only
just-runit cache clear <url>     # remove the entry for one specific URL
just-runit cache -h              # show cache subcommand help
```

### `just-runit version`

Prints `just-runit vX.Y.Z` and exits.

### `just-runit help`

```
just-runit help
just-runit -h
just-runit            # bare invocation also prints help
```
