# setup-system

`setup-system` takes a freshly installed machine to a working one: system
packages, an opinionated bash configuration, ssh, git defaults, and dev
tooling. It runs ephemerally via [`jbx`](just-runit.md) — no local
installation required.

```bash
jbx setup-system --dry-run     # see the whole plan, change nothing
jbx setup-system               # do it
jbx setup-system -s shell      # just the bash configuration
```

Every step is idempotent. Re-running `setup-system` is how you pick up a newer
template on a machine you set up months ago, not a mistake.

______________________________________________________________________

## Steps

| Step     | What it does                                                                                                                                                  |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `deps`   | Installs system packages from `jb.toml` / `jb-deps.toml` in the current directory, via [`install-deps`](install-deps.md). Skipped when there is no deps file. |
| `shell`  | Installs the bash configuration to `~/.config/just-bashit/` and adds one source line to `~/.bashrc` and `~/.profile`.                                         |
| `ssh`    | Fixes `~/.ssh` permissions and creates an ed25519 key named after this host if there is no key at all. Prints the public key.                                 |
| `git`    | Sets global git defaults that are not already set. Never touches `user.name` or `user.email`.                                                                 |
| `tools`  | Installs `uv` if missing; installs pre-commit hooks when the current directory is a repo with `.pre-commit-config.yaml`.                                      |
| `claude` | Installs Claude Code if the `claude` command is missing.                                                                                                      |

They always run in that order, whatever order you list them in — packages
land before the steps that need `git`, `curl` and `ssh-keygen`.

```bash
jbx setup-system -s shell,ssh      # only these
jbx setup-system -x claude,deps    # everything except these
```

To change the default set for a project, declare it in `jb.toml`:

```toml
[tools.setup-system]
source = "just-bashit:setup-system"
steps  = ["deps", "shell", "git"]
```

`-s` always overrides that, regardless of the toml setting.

______________________________________________________________________

## The shell step

Your `~/.bashrc` is yours. The `shell` step never rewrites it — it installs
two files of its own and appends one line that sources each:

```
~/.config/just-bashit/
    bashrc.sh      interactive settings — readline, history, aliases, prompt
    profile.sh     environment — PATH, EDITOR, ssh-agent
    bashrc.d/      your additions; sourced last, never overwritten
```

```bash
# appended to ~/.bashrc
if [ -r "$HOME/.config/just-bashit/bashrc.sh" ]; then . "$HOME/.config/just-bashit/bashrc.sh"; fi

# appended to ~/.profile (and ~/.bash_profile, when that file exists)
if [ -r "$HOME/.config/just-bashit/profile.sh" ]; then . "$HOME/.config/just-bashit/profile.sh"; fi
```

Uninstalling is deleting those lines. Re-running with a newer just-bashit
replaces `bashrc.sh` and `profile.sh` in place, keeping the copy it replaced
as `bashrc.sh.bak`.

### Why two files

Every distro's stock `~/.bashrc` opens with an interactive-only guard:

```bash
case $- in *i*) ;; *) return;; esac
```

Anything exported below that line is invisible to non-interactive shells —
`ssh host git push`, cron, CI, and the subprocesses your editor and agents
spawn. A `PATH` or `SSH_AUTH_SOCK` set in `.bashrc` therefore works when you
type it and fails when a script does.

So environment lives in `profile.sh`, read by login shells, and interactive
settings live in `bashrc.sh`. Because terminal emulators start *non-login*
shells that never read `~/.profile`, `bashrc.sh` sources `profile.sh` itself
when no login shell has already done so. Both paths converge; neither
duplicates the other.

`profile.sh` is written in POSIX sh, not bash, because `~/.profile` is also
read by dash and by desktop session managers.

!!! tip "Put your own settings in `bashrc.d/`"

    `~/.config/just-bashit/bashrc.d/*.sh` is sourced last, so anything there
    wins over the template and survives the next `setup-system` run.

### What you get

**Arrow keys search history.** Type `ssh ` and press Up: you get your last
`ssh` command, not your last command. Each key is bound in both normal
(`\e[A`) and application (`\eOA`) cursor modes, so it works in tmux and
screen as well as a bare terminal.

**An ssh-agent that already has your keys.** `profile.sh` adopts an inherited
agent if there is one — forwarded, systemd socket-activated, gnome-keyring,
1Password — and only starts its own if nothing is listening, on a fixed
socket path so the next login reuses it instead of leaking an agent per
shell. `bashrc.sh` then adds any `~/.ssh/NAME` that has a matching `NAME.pub`
and is not already loaded, which is why passphrase prompts happen once per
key per boot rather than once per terminal.

**History that survives.** 100 000 entries, deduplicated, timestamped,
appended rather than overwritten, and flushed at every prompt — closing one
terminal never discards what another one recorded.

**A prompt worth the columns.** `[✗2] ~/code/project (main*) $` — exit status
only after a failure, `user@host` only when the session is remote or
containerised, git branch from `symbolic-ref` and a tracked-file diff rather
than `git status`, which stalls the prompt in large repos.

Plus: colour `ls`/`grep`/`diff` probed rather than assumed (GNU takes
`--color=auto`, BSD takes `-G`), `ll`/`la`/`..`/`...`, `mkcd`, interactive
guards on `rm`/`cp`/`mv`, bash 4 shell options behind a version check so
macOS's bash 3.2 does not error, and bash-completion loaded from whichever
of five paths this distro or Homebrew prefix uses.

### Opt-outs

Set any of these in `~/.bashrc` *before* the source line:

| Variable            | Effect                                            |
| ------------------- | ------------------------------------------------- |
| `JB_SSH_AGENT=0`    | Do not start or adopt an ssh-agent                |
| `JB_SSH_AUTOADD=0`  | Agent yes, but do not add `~/.ssh` keys to it     |
| `JB_PATH=0`         | Leave `PATH` alone                                |
| `JB_PROMPT=0`       | Leave `PS1` alone                                 |
| `JB_PROMPT_GIT=0`   | Prompt without the git branch                     |
| `JB_PROMPT_COLOR=0` | Prompt without colour                             |
| `JB_READLINE=0`     | No key bindings                                   |
| `JB_ALIASES=0`      | No aliases                                        |
| `JB_SAFE_ALIASES=0` | Aliases, but no interactive `rm`/`cp`/`mv` guards |
| `JB_COMPLETION=0`   | Do not load bash-completion                       |

______________________________________________________________________

## The ssh step

Creates a key only when `~/.ssh` holds no private key with a matching
`.pub` — a machine that already has an identity does not get another one.
The key is ed25519, named after the host, and the public half is printed
with the `gh` command to register it:

```bash
jbx setup-system -s ssh
# generating ed25519 key /home/you/.ssh/workstation
# ...
# gh ssh-key add /home/you/.ssh/workstation.pub --title 'workstation'
```

`--key-name NAME` overrides the filename.

!!! warning "`--yes` creates the key with an empty passphrase"

    Without `--yes`, `ssh-keygen` prompts for a passphrase as usual. With
    `--yes` there is nothing to prompt on, so the key is written unprotected —
    appropriate for a throwaway VM or a container, not for a laptop.

______________________________________________________________________

## The git step

Sets these only when the key has no value already, so nothing you have
chosen is overwritten:

| Key                    | Value     |
| ---------------------- | --------- |
| `init.defaultBranch`   | `main`    |
| `pull.rebase`          | `true`    |
| `rebase.autoStash`     | `true`    |
| `push.default`         | `simple`  |
| `push.autoSetupRemote` | `true`    |
| `fetch.prune`          | `true`    |
| `diff.colorMoved`      | `zebra`   |
| `color.ui`             | `auto`    |
| `core.editor`          | `$EDITOR` |

`user.name` and `user.email` are deliberately absent: identity belongs to
the repository, not the machine. Set it per repo with
`git config user.email you@example.com`.

______________________________________________________________________

## Options

| Flag       | Long form                   | Description                                        |
| ---------- | --------------------------- | -------------------------------------------------- |
| `-h`       | `--help`                    | Show help and exit                                 |
| `-n`       | `--dry-run`                 | Print the plan; change nothing                     |
| `-v`       | `--verbose`                 | Print extra detail                                 |
| `-y`       | `--yes`                     | Never prompt (see the ssh warning above)           |
| `-s STEPS` | `--steps STEPS`             | Comma-separated steps to run                       |
| `-x STEPS` | `--skip STEPS`              | Comma-separated steps to leave out                 |
|            | `--prefix DIR`              | Config directory (default `~/.config/just-bashit`) |
|            | `--key-name NAME`           | ssh key filename (default: this hostname)          |
|            | `--template [PATH]`         | Write the bashrc template to PATH, or stdout       |
|            | `--template-profile [PATH]` | Write the profile template to PATH, or stdout      |

______________________________________________________________________

## Examples

### Set up a new machine from scratch

```bash
curl -fsSL https://just-buildit.github.io/get-jb.sh | bash
jbx setup-system
exec bash -l
```

### Read the templates without installing anything

```bash
jbx setup-system --template          # the interactive half
jbx setup-system --template-profile  # the environment half
```

### Take the shell config and nothing else

```bash
jbx setup-system -s shell
```

### Provision a CI runner or container

```bash
jbx setup-system -y -x claude,tools
```

### Use it as your project's onboarding command

```toml
# jb.toml
[tools.setup-system]
source = "just-bashit:setup-system"
steps  = ["deps", "tools"]

[dev.apt]
packages = ["build-essential", "cmake"]

[dev.pacman]
packages = ["base-devel", "cmake"]
```

```bash
jbx setup-system     # installs the project's packages, then uv + hooks
```

______________________________________________________________________

## Dry run

`--dry-run` prints every command it would run and writes nothing at all —
no files, no config, no packages:

```bash
jbx setup-system -n -s shell,git
```

```
just-bashit setup-system
dry run — nothing will be changed

==> shell — bash configuration
    would run: mkdir -p /home/you/.config/just-bashit ...
    creating:   /home/you/.config/just-bashit/bashrc.sh
    would append to /home/you/.bashrc: if [ -r "$HOME/... "; fi

==> git — global defaults
    git config --global init.defaultBranch main
    ...

summary
    shell:   ok (/home/you/.config/just-bashit)
    git:     ok (9 default(s) set)
```

______________________________________________________________________

## Shell compatibility

`setup-system.sh` needs **bash 3.2 or later** — the system bash on macOS
qualifies. The installed `bashrc.sh` degrades on the same footing: bash 4
shell options are behind a version check, and readline settings that need a
newer readline fail silently rather than erroring.

`profile.sh` is POSIX sh and is safe to source from dash.
