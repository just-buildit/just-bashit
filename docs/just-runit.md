# just-runit

`just-runit` (alias: `jr`) is an ephemeral bash tool runner. Fetch a script from a URL, call a
function it defines, then discard — no installation, no leftover environment
pollution. The bash equivalent of `uvx`, for anything reachable over HTTPS.

!!! danger "You are responsible for what you run"
    `jr` fetches and executes arbitrary code from any URL you provide.
    It performs no review, scanning, or sandboxing of remote scripts.
    There is no safety guarantee of any kind — that responsibility
    belongs entirely to you. Always inspect a script before running it.

```bash
just-runit jbs:datetime iso-8601-basic -m
# 20260522T174523.841Z
```

---

## Getting just-runit

Source the install script — it downloads `just-runit`, drops a `jr` symlink
in `~/.local/bin`, and exports the updated `PATH` into your current shell
immediately (no new terminal needed):

```bash
. <(curl -sSL https://just-buildit.github.io/get-just-runit.sh)
```

That's it. `jr` is live in the shell you ran that in.

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

Or pull it directly with itself once you have any copy handy:

```bash
just-runit gh:just-buildit/just-bashit/src/just-runit   # script mode — runs itself
```

---

## How it works

```
just-runit [OPTIONS] URL [FUNCTION [ARGS...]]
```

`just-runit` fetches `URL`, sources it into a subshell, optionally calls `FUNCTION`
with `ARGS`, then exits. The subshell boundary is the isolation — nothing leaks
back to the calling shell, the same way a subprocess boundary works with
`sudo`.

Fetched scripts are cached at `${XDG_CACHE_HOME:-$HOME/.cache}/just-runit/` and
reused on subsequent calls until the TTL expires (default 1 hour).

---

## URL shortcuts

| Prefix | Expands to |
|---|---|
| `jbs:LIBRARY` | `just-bashit` library from the main branch |
| `gh:USER/REPO/PATH` | GitHub raw content, default branch |
| `gh:USER/REPO/PATH@REF` | GitHub raw content at a specific ref/tag/SHA |
| `https://...` | Any HTTPS URL |

```bash
# just-bashit shorthand
just-runit jbs:logging log -t SUCCESS "deployed"

# GitHub shorthand, pinned to a tag
just-runit gh:user/repo/scripts/deploy.sh@v1.4.0 run --env prod

# Full URL
just-runit https://example.com/tools/setup.sh configure
```

!!! note "jbs: dependency resolution"
    Libraries like `logging` and `network` depend on other just-bashit
    libraries. When you use `jbs:`, `just-runit` co-fetches the entire `src/`
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
just-runit -l jbs:logging
# color-echo
# is-number
# iso-8601-basic
# log
# log-wait
# trim-from
```

**Pin to a checksum for auditable CI use:**

```bash
just-runit -k sha256:abc123def456 https://infra.example.com/bootstrap.sh setup
```

**Clean environment — script sees only HOME, TERM, PATH:**

```bash
just-runit -c https://example.com/tool.sh run
```

**Pass specific vars into a clean environment:**

```bash
just-runit -c -p DEPLOY_TOKEN,AWS_REGION https://example.com/deploy.sh run
```

**Force a fresh fetch (e.g. after a release):**

```bash
just-runit -r jbs:logging log "refreshed"
```

**Skip the cache entirely — nothing touches disk:**

```bash
just-runit -n https://example.com/ephemeral.sh do-thing
```

**Script mode — no function name, just source and run:**

```bash
just-runit https://example.com/setup.sh   # runs whatever the script does top-level
```

**One-liner in CI:**

```bash
just-runit jbs:network test-internet-access -vt 10 || exit 1
```
