# just-runit

`just-runit` (alias: `jx`) is an ephemeral bash tool runner. Fetch a script from a URL or
namespace, call a function it defines, then discard — no installation, no leftover environment
pollution. The bash equivalent of `uvx`, for anything reachable over HTTPS.

!!! danger "You are responsible for what you run"
    `jx` fetches and executes arbitrary code from any URL you provide.
    It performs no review, scanning, or sandboxing of remote scripts.
    There is no safety guarantee of any kind — that responsibility
    belongs entirely to you. Always inspect a script before running it.

```bash
jx just-bashit:datetime iso-8601-basic -m
# 20260522T174523.841Z
```

---

## Getting just-runit

Source the install script — it downloads `just-runit`, drops a `jx` symlink
in `~/.local/bin`, and exports the updated `PATH` into your current shell
immediately (no new terminal needed):

```bash
. <(curl -sSL https://just-buildit.github.io/get-just-runit.sh)
```

That's it. `jx` is live in the shell you ran that in.

!!! warning "Use at your own risk"
    This script is provided as-is, without warranty of any kind. It writes
    to `~/.local/bin` and may modify `~/.bashrc`. The tool it installs
    runs arbitrary remote code with no safety guarantees — you are solely
    responsible for what you choose to run with it. Review the source before
    running: [get-just-runit.sh](https://just-buildit.github.io/get-just-runit.sh)

!!! note "Why source instead of pipe to bash?"
    `. <(...)` runs the script in the current shell process, so
    `export PATH=...` reaches you directly. `bash <(...)` or
    `curl ... | bash` spawn a subshell — PATH changes die with it.

---

## How it works

```
jx [OPTIONS] SPEC [FUNCTION [ARGS...]]
```

`jx` resolves `SPEC` to a script URL, fetches it, sources it into a subshell,
optionally calls `FUNCTION` with `ARGS`, then exits. The subshell boundary is
the isolation — nothing leaks back to the calling shell.

Fetched scripts are cached at `${XDG_CACHE_HOME:-$HOME/.cache}/just-runit/` and
reused on subsequent calls until the TTL expires (default 1 hour).

---

## SPEC forms

| Form | Example | Resolves to |
|---|---|---|
| `NAME` | `install-deps` | default namespace (`just-buildit.github.io`) via `aliases.toml` then direct probe |
| `NS:NAME` | `just-bashit:logging` | namespace `NS` — built-in: `just-buildit`, `just-bashit` |
| `gh:USER/REPO/PATH` | `gh:user/repo/tool.sh` | GitHub raw content, default branch `main` |
| `gh:USER/REPO/PATH@REF` | `gh:user/repo/tool.sh@v2.1.0` | GitHub raw content at a specific ref/tag/SHA |
| `https://...` | `https://example.com/tool.sh` | Any HTTPS URL |

**Resolution order for `NAME` / `NS:NAME`:**

1. Look up `NAME` in the namespace's `aliases.toml` (cached)
2. Probe `NS_BASE/NAME.sh` then `NS_BASE/NAME.py`
3. Error if neither resolves

```bash
# Default namespace (just-buildit.github.io)
jx install-deps -s apt

# Explicit just-bashit namespace
jx just-bashit:logging log -t SUCCESS "deployed"

# GitHub shorthand, pinned to a tag
jx gh:user/repo/scripts/deploy.sh@v1.4.0 run --env prod

# Full URL
jx https://example.com/tools/setup.sh configure
```

!!! note "just-bashit namespace co-fetch"
    Libraries like `logging` and `network` depend on other just-bashit
    libraries. When you use `just-bashit:NAME`, `jx` co-fetches the entire `src/`
    directory into a single cache folder so relative inter-source calls
    resolve correctly — you don't have to manage this yourself.

---

## Options

| Flag | Description |
|---|---|
| `-l` | List functions the script defines, then exit |
| `-r` | Refresh — re-fetch even if the cache is fresh |
| `-n` | No-cache — fetch once and discard (nothing written to disk) |
| `-c` | Clean environment (minimal env, like `sudo` without `-E`) |
| `-p VARS` | Comma-separated vars to pass through when using `-c` |
| `-t TTL` | Cache TTL in seconds. Default `3600`. `0` = keep forever |
| `-k HASH` | Verify before running: `sha256:HASH` or `md5:HASH` |
| `-v` | Verbose — prints fetch/cache activity to stderr |

---

## Recipes

**Discover what a script exposes before calling it:**

```bash
jx -l just-bashit:logging
# color-echo
# is-number
# iso-8601-basic
# log
# log-wait
# trim-from
```

**Pin to a checksum for auditable CI use:**

```bash
jx -k sha256:abc123def456 https://infra.example.com/bootstrap.sh setup
```

**Clean environment — script sees only HOME, TERM, PATH:**

```bash
jx -c https://example.com/tool.sh run
```

**Pass specific vars into a clean environment:**

```bash
jx -c -p DEPLOY_TOKEN,AWS_REGION https://example.com/deploy.sh run
```

**Force a fresh fetch (e.g. after a release):**

```bash
jx -r just-bashit:logging log "refreshed"
```

**Skip the cache entirely — nothing touches disk:**

```bash
jx -n https://example.com/ephemeral.sh do-thing
```

**Script mode — no function name, just source and run:**

```bash
jx https://example.com/setup.sh   # runs whatever the script does top-level
```

**One-liner in CI:**

```bash
jx just-bashit:network test-internet-access -vt 10 || exit 1
```
