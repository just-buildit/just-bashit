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

### From PowerShell (Windows)

```powershell
irm https://just-buildit.github.io/get-jb.ps1 | iex
jbx setup-system
```

`get-jb.ps1` runs in Windows PowerShell 5.1 and PowerShell 7. jbx is bash, so
bash is still what runs it — but as a runtime you never open:

1. It finds Git for Windows' `bash.exe` (the registry, the `git` on `PATH`,
    then the default install directories) and never the WSL launcher in
    `System32`. With none, it installs `Git.Git` with winget (a machine-wide
    install, so one UAC prompt) and looks again.
1. With no `uv` on `PATH`, it installs `astral-sh.uv` with winget, so an ARM64
    machine gets the native build, and puts winget's Links directory on this
    session's `PATH` so bash sees it. On ARM64 winget also installs uv's
    dependency, the Arm64 Visual C++ Redistributable, which asks for elevation:
    expect one UAC prompt there.
1. It runs `get-jb.sh` in that bash — the same installer as above, so a
    `JB_REINSTALL=1` set in the session reaches it.
1. It writes `jbx` and `just-runit` **functions** into a marked block of your
    profile and defines them in the current session. Re-running rewrites the
    block in place.

The block goes in the `CurrentUserAllHosts` profile of **both** editions —
`Documents\WindowsPowerShell\profile.ps1` and `Documents\PowerShell\profile.ps1`
— since they read different files and `setup-system` installs PowerShell 7 on a
machine that has only 5.1. `JB_PS_PROFILE` names one file to use instead.

The functions forward arguments, piped input and the exit code (`$LASTEXITCODE`).
Arguments travel in the environment to a small driver,
`%LOCALAPPDATA%\just-bashit\jbx-ps.sh`, not on bash's command line, which the
MSYS runtime would glob (`*`) and re-quote (`'`, `"`): each one arrives as
typed, empty ones included. Two things are PowerShell's own and happen before
jbx sees anything: a bare `--` is consumed by PowerShell, and an unquoted
`$name` is expanded by it.

!!! warning "Windows PowerShell 5.1 and the execution policy"

    5.1 runs a profile only when the execution policy allows scripts, and a
    fresh Windows client is `Restricted`. `get-jb.ps1` warns rather than
    changing a security setting; `jbx` works in the session that ran it, and
    for new sessions run
    `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`. PowerShell 7's
    default already allows it.

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

| Form                                       | Example                                        | Resolves to                                                                       |
| ------------------------------------------ | ---------------------------------------------- | --------------------------------------------------------------------------------- |
| `NAME`                                     | `install-deps`                                 | default namespace (`just-buildit.github.io`) via `aliases.toml` then direct probe |
| `NS:NAME`                                  | `just-bashit:logging`                          | namespace `NS` — built-in: `just-buildit`, `just-bashit`, `just-makeit`           |
| `gh:USER/REPO/PATH`                        | `gh:user/repo/tool.sh`                         | GitHub raw content, default branch `main`                                         |
| `gh:USER/REPO/PATH@REF`                    | `gh:user/repo/tool.sh@v2.1.0`                  | GitHub raw content at a specific ref/tag/SHA                                      |
| `https://...`                              | `https://example.com/tool.sh`                  | Any HTTPS URL                                                                     |
| `[FORGE+]https://HOST/PROJECT//PATH[@REF]` | `https://gitlab.com/acme/tools//ci/tool.sh@v2` | A script by its path in a repository; see [Repository URLs](#repository-urls)     |

**Resolution order for `NAME` / `NS:NAME`:**

1. Look up `NAME` in the namespace's `aliases.toml` (cached)
1. Probe `NS_BASE/NAME.sh` then `NS_BASE/NAME.py`
1. Error if neither resolves

```bash
# Default namespace (just-buildit.github.io)
jbx install-deps -s apt

# Explicit just-bashit namespace
jbx just-bashit:logging log -t SUCCESS "deployed"

# Explicit just-makeit namespace
jbx just-makeit:install-deps

# GitHub shorthand, pinned to a tag
jbx gh:user/repo/scripts/deploy.sh@v1.4.0 run --env prod

# Full URL
jbx https://example.com/tools/setup.sh configure

# A script in a repository, on any supported forge
jbx https://gitlab.com/acme/tools//ci/deploy.sh@v1.4.0 run --env prod
```

!!! note "just-makeit namespace"

    `just-makeit:NAME` is an ordinary URL-base namespace, like the default
    one, rooted at `https://just-buildit.github.io/just-makeit`. It holds the
    tools that just-makeit publishes for its own users, such as
    `install-deps` (the build-dependency installer). It resolves through that
    site's `aliases.toml` first, then the direct `NAME.sh` / `NAME.py` probe,
    and has no co-fetch bundle.

!!! note "just-bashit namespace co-fetch"

    Libraries like `logging` and `network` depend on other just-bashit
    libraries. When you use `just-bashit:NAME`, `jbx` co-fetches the entire `src/`
    directory into a single cache folder so relative inter-source calls
    resolve correctly — you don't have to manage this yourself.

### Repository URLs

Name a script by the repository it lives in and its path there, instead of
by a host's raw-content URL:

```text
[FORGE+]https://HOST[:PORT]/PROJECT//PATH[@REF]
```

- **`//`** separates the repository from the path inside it. It cannot be a
    colon, since the scheme and a port already use one. A URL path never
    holds `//`, so an ordinary script URL keeps its meaning.
- **`@REF`** is a branch, tag or commit SHA. Without it, jbx fetches `HEAD`,
    the repository's default branch. (`gh:` keeps its `main` default.) A ref
    containing `/` is refused, because a raw URL cannot tell it from the
    path; pin a tag or SHA instead.
- **`FORGE+`** says which forge serves the host. The four public hosts below
    need no prefix. Any other host must name its forge, because jbx does not
    guess a raw-file layout. An unknown host is refused, and the error says
    which prefix to add.

| `FORGE`              | Known host      | Fetches                                                                          | Covers                                         |
| -------------------- | --------------- | -------------------------------------------------------------------------------- | ---------------------------------------------- |
| `github`             | `github.com`    | `raw.githubusercontent.com/O/R/REF/PATH` (another host: `HOST/O/R/raw/REF/PATH`) | GitHub, GitHub Enterprise Server               |
| `gitlab`             | `gitlab.com`    | `HOST/GROUP/.../PROJECT/-/raw/REF/PATH`                                          | GitLab.com, self-managed GitLab; nested groups |
| `gitea` or `forgejo` | `codeberg.org`  | `HOST/O/R/raw/REF/PATH`                                                          | Gitea, Forgejo, Codeberg                       |
| `bitbucket`          | `bitbucket.org` | `bitbucket.org/O/R/raw/REF/PATH`                                                 | Bitbucket Cloud only                           |

```bash
jbx https://github.com/acme/tools//bin/tool.sh                 # default branch
jbx https://codeberg.org/acme/tools//tool.sh@v2 say hi         # a tag, then fn + args
jbx gitea+https://git.example.com:3000/ops/tools//deploy.sh@0123abc deploy
jbx gitlab+https://gitlab.example.com/platform/ci/tools//lint.sh
```

The repository URL resolves to the raw URL in the table, which is then
fetched like any other URL. Caching, `-r`, `-n`, `-k HASH`, `-f`, `-l`,
`--no-verify`, function calls and argument forwarding all behave as they do
for a plain URL.

**Transports and authentication.** Fetching is HTTPS only, and the TLS
certificate is checked. jbx sends no credentials and fetches straight from the
host, never through a third-party service, so a private repository fails as
it would for an anonymous browser. These are refused, each with an error
saying what to use instead:

- `http://`, `ssh://` and `git@host:` URLs;
- credentials in the URL (`user:token@host`), which would otherwise be
    written to logs and cache metadata;
- Bitbucket Server and Data Center, which serve raw files on another layout;
- an empty or absolute path, or one containing `..`;
- a repository that is not `OWNER/REPO`, except for GitLab groups.

______________________________________________________________________

## Options

| Flag          | Description                                                     |
| ------------- | --------------------------------------------------------------- |
| `-l`          | List functions the script defines, then exit (see below)        |
| `-f`          | Fetch only — cache the script, print its path, run nothing      |
| `-r`          | Refresh — re-fetch even if the cache is fresh                   |
| `-n`          | No-cache — fetch fresh, discard on exit; the cache is untouched |
| `-c`          | Clean environment (minimal env, like `sudo` without `-E`)       |
| `-p VARS`     | Comma-separated vars to pass through when using `-c`            |
| `-t TTL`      | Cache TTL in seconds. Default `3600`. `0` = keep forever        |
| `-k HASH`     | Verify before running: `sha256:HASH` or `md5:HASH`              |
| `-v`          | Verbose — prints fetch/cache activity to stderr                 |
| `--no-verify` | Skip TLS certificate checks on jbx's own downloads (see below)  |

### `--no-verify`

Some networks re-sign TLS with a CA of their own, usually a proxy that
inspects traffic. On a box that does not trust that CA, every jbx download
fails with a certificate error. `--no-verify` makes jbx's own downloads skip
the check, as `curl --insecure` does. That covers the script, the
`aliases.toml` lookup, the just-bashit co-fetch bundle, the probe that
resolves a bare name, and the nested uv install. It prints a warning on
every run.

```bash
jbx --no-verify -k sha256:abc123def456 https://example.com/tool.sh run
```

- It has no short form, since `-k` is the checksum, so it is hard to type by
    accident. It is read only before SPEC: `jbx tool.sh --no-verify` passes
    the flag to the script.
- Without TLS checks, anything on the path can change what is downloaded.
    Pin `-k HASH` so the script is still verified before it runs.
- It changes only the downloads jbx makes. A script that fetches more
    (`install-deps`, `setup-system`) does so with its own curl and the box's
    CA store, so trusting the CA is the lasting fix.

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

`-n` neither reads nor writes any of it: the script, the co-fetch bundle and
aliases.toml go to a temporary directory under `$TMPDIR`, removed when the run
exits.

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

`-l` lists a shell script's functions by **reading** it: nothing in the
script runs, not its top-level commands and not the command substitutions in
its assignments, so it lists any script, main guard or not:

```bash
jbx -l just-bashit:setup-system   # lists; sets nothing up
```

It lists the functions defined at the script's top level and inside a
top-level `if`, then those of each file the script sources (`source FILE` /
`. FILE`), read the same way. A sourced file is found from its path as
written, never by evaluating it: a literal path as it is, and a path built
from an expansion, such as `source "${_SCRIPT_DIR}/toml.sh"`, by its last
component beside the script, which is where jbx co-fetches a just-bashit
script's libraries. One it cannot find is named on stderr and its functions
are not listed. A Python script is parsed (`ast`), never run.

Running is the other half of the same contract: `jbx SPEC` and
`jbx SPEC FUNCTION` both run the script's top level exactly once, as
sourcing it would. A FUNCTION the script does not define exits 127.

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
`jbx` calls for those tools are instant cache hits. Nothing is run: each tool
is fetched as `just-runit -f` fetches it.

```
  reading /path/to/project/bootstrap.toml
  -> just-bashit:install-deps ok
```

A legacy `jb.toml` met on the walk, before any `bootstrap.toml`, is refused
with the rename to make. See [bootstrap.toml](bootstrap-toml.md).

`just-runit install --no-verify` fetches every tool with
[`--no-verify`](#-no-verify).

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
