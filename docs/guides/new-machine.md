# Setting up a new machine

A start-to-finish walkthrough: bare OS to a working shell, using
[`setup-system`](../setup-system.md). That page is the reference — every flag,
every step, every option. This one is the narrative: what to run, what it does
to your machine, how to check it worked, and what to do when it didn't.

______________________________________________________________________

## The short version

```bash
. <(curl -sSL https://just-buildit.github.io/get-jb.sh)   # get jb + jbx
jbx setup-system --dry-run                                # read the plan
jbx setup-system                                          # run it
exec bash -l                                              # apply it
```

Four commands. The rest of this page is what each one does and why you might
want to deviate.

______________________________________________________________________

## Before you start

`setup-system` needs `bash` 3.2 or newer and `curl`. Everything else it either
installs or skips with a note.

It will:

- write two files under `~/.config/just-bashit/` and append **one line** to
    each of `~/.bashrc` and `~/.profile`
- create an ssh key **only** if `~/.ssh` has none
- set git defaults **only** where you have not already set a value
- install packages from a `jb.toml` in the current directory, if there is one

It will not: touch anything else in your `~/.bashrc`, set `user.name` or
`user.email`, replace a key you already have, or overwrite a git setting you
chose. Re-running it is how you upgrade, not a mistake.

!!! tip "Read the plan first"

    `--dry-run` prints every command it would run and writes nothing at all.
    On a machine you care about, run that before the real thing.

______________________________________________________________________

## Step 1 — get `jb` and `jbx`

```bash
. <(curl -sSL https://just-buildit.github.io/get-jb.sh)
```

Sourced rather than piped to `bash`, so the `PATH` change applies to the shell
you are sitting in. If you pipe it instead, open a new shell afterwards.

`jbx` fetches a script, runs it, and discards it — nothing is installed for
`setup-system` itself. See [just-runit](../just-runit.md).

______________________________________________________________________

## Step 2 — look at the plan

```bash
jbx setup-system --dry-run
```

```
just-bashit setup-system
dry run — nothing will be changed

==> deps — system packages
    no jb.toml or jb-deps.toml in /home/you — nothing to install
==> shell — bash configuration
    creating:   /home/you/.config/just-bashit/bashrc.sh
    would append to /home/you/.bashrc: if [ -r "$HOME/... "; fi
...
summary
    deps:    skipped (no deps file)
    shell:   ok (/home/you/.config/just-bashit)
```

The summary at the end is the thing to read: one line per step, saying what
happened or why it didn't.

______________________________________________________________________

## Step 3 — run it

```bash
jbx setup-system
```

Or a subset — the steps are independent and always run in dependency order,
whatever order you name them in:

```bash
jbx setup-system -s shell,ssh     # only these
jbx setup-system -x claude,tools  # everything except these
```

The `ssh` step will prompt for a key passphrase if it generates one. Nothing
else is interactive.

______________________________________________________________________

## Step 4 — apply it

```bash
exec bash -l
```

Your current shell has already read its rc files; nothing you install changes
it retroactively. A login shell (`-l`) is what picks up `~/.profile`, so use
that rather than plain `exec bash` the first time.

______________________________________________________________________

## What changed on disk

```
~/.config/just-bashit/
    bashrc.sh      interactive settings — readline, history, aliases, prompt
    profile.sh     environment — PATH, EDITOR, ssh-agent
    bashrc.d/      yours; sourced last, never overwritten
```

Plus one line in each of two files:

```bash
# ~/.bashrc
if [ -r "$HOME/.config/just-bashit/bashrc.sh" ]; then . "$HOME/.config/just-bashit/bashrc.sh"; fi

# ~/.profile  (and ~/.bash_profile, if that file exists)
if [ -r "$HOME/.config/just-bashit/profile.sh" ]; then . "$HOME/.config/just-bashit/profile.sh"; fi
```

That is the whole footprint. Upgrading replaces the two files and keeps the
old copy as `bashrc.sh.bak`; uninstalling is deleting the two lines.

______________________________________________________________________

## Which file gets read when

The split between the two files is the one design decision worth
understanding, because it is what makes tooling outside your terminal work.
Measured, not assumed:

| how the shell starts                    | reads `profile.sh`     | reads `bashrc.sh` |
| --------------------------------------- | ---------------------- | ----------------- |
| console or `ssh host` login             | ✅                     | ❌                |
| terminal emulator tab                   | ✅ *(via `bashrc.sh`)* | ✅                |
| `bash -lc '…'`                          | ✅                     | ❌                |
| `bash -c '…'` from a configured session | inherited              | ❌                |
| `ssh host CMD`                          | ❌                     | ❌                |

The stock `~/.bashrc` on every distro opens with an interactive-only guard:

```bash
case $- in *i*) ;; *) return;; esac
```

So exports placed there reach interactive terminals and nothing else.
`~/.profile` runs once per **login session**, and everything descended from
that session inherits its exports — scripts, language servers, agents, GUI
apps. That is why `PATH` and `SSH_AUTH_SOCK` live in `profile.sh`.

Because terminal emulators start *non-login* shells that never read
`~/.profile`, `bashrc.sh` sources `profile.sh` itself when no login shell has.
Both paths converge; neither duplicates the other.

!!! warning "`ssh host CMD` reads neither file"

    A remote command runs a non-login, non-interactive shell, which consults
    no rc file at all — that is bash's behaviour, not something this
    configuration changes. If `ssh host 'git push'` cannot find something,
    use a login shell explicitly:

    ```bash
    ssh host -t bash -lc 'git push'
    ```

    or put the variable in `~/.ssh/environment` with `PermitUserEnvironment`.

______________________________________________________________________

## Checking it worked

```bash
# arrows search history rather than walking it
bind -q history-search-backward
# → history-search-backward can be invoked via "\eOA", "\e[A".
#   (some builds print the same sequences as "\M-OA", "\M-[A")

# one agent, holding your keys
echo "$SSH_AUTH_SOCK"
ssh-add -l

# the environment reaches non-terminal children
bash -lc 'bash -c "echo \$PATH"' | tr : '\n' | grep local/bin
```

Then the real test: press <kbd>↑</kbd> after typing a couple of characters.
You should get your last command *starting with those characters*, not simply
your last command.

______________________________________________________________________

## Making it yours

**Add things** in `~/.config/just-bashit/bashrc.d/*.sh`. Sourced last, so they
win, and untouched by upgrades.

```bash
cat > ~/.config/just-bashit/bashrc.d/50-work.sh <<'EOF'
alias k=kubectl
export AWS_PROFILE=dev
EOF
```

**Turn things off** with a `JB_*` variable set in `~/.bashrc` *above* the
source line. The full table is in the
[reference](../setup-system.md#opt-outs); the ones people reach for:

| Variable            | Effect                                               |
| ------------------- | ---------------------------------------------------- |
| `JB_PROMPT_GIT=0`   | Prompt without the git branch — for very large repos |
| `JB_SAFE_ALIASES=0` | No interactive `rm`/`cp`/`mv` guards                 |
| `JB_SSH_AUTOADD=0`  | Start an agent, but do not load keys into it         |
| `JB_PROMPT=0`       | Keep your own `PS1`                                  |

**Move the install** with `--prefix DIR` if `~/.config` is not where you want
it.

______________________________________________________________________

## Per-environment notes

=== "WSL2"

    Works unmodified. `XDG_RUNTIME_DIR` is usually absent, so the agent
    socket lands under `$TMPDIR` (or `/tmp`) in a 0700 directory instead —
    same lifetime, same single agent per user.

=== "macOS"

    The system `/bin/bash` is 3.2, from 2007. Everything here accounts for
    that: bash 4 shell options are behind a version check and readline
    settings that need a newer readline fail quietly.

    One trap that is not ours: if `~/.bash_profile` exists, bash reads it
    for login shells and **ignores `~/.profile` entirely**. `setup-system`
    keeps both in step when both are present.

=== "Containers and CI"

    Skip what a container has no use for, and never wait on a prompt:

    ```bash
    jbx setup-system -y -x claude,tools
    ```

    `--yes` means no prompts — which for the ssh step means a key with an
    **empty passphrase**. Right for an ephemeral runner, wrong for a laptop.

=== "Shared or headless servers"

    The shell configuration is per-user and needs no root. `deps` is the
    only step that uses `sudo`, so drop it:

    ```bash
    jbx setup-system -x deps
    ```

______________________________________________________________________

## Using it as your project's onboarding command

Declare the steps and the system packages in `jb.toml`, and a new contributor
runs one command:

```toml
[tools.setup-system]
source = "just-bashit:setup-system"
steps  = ["deps", "tools"]

[dev.apt]
packages = ["build-essential", "cmake"]

[dev.pacman]
packages = ["base-devel", "cmake"]
```

```bash
jbx setup-system
```

They get the project's system packages and `uv` + pre-commit hooks, and not
your opinions about their prompt. `-s` on the command line always overrides
the `steps` key, so anyone who does want the shell config can ask for it.

______________________________________________________________________

## Troubleshooting

| Symptom                                | Cause                                                 | Fix                                                                                                                  |
| -------------------------------------- | ----------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Nothing changed                        | The shell you ran it in had already read its rc files | `exec bash -l`                                                                                                       |
| <kbd>↑</kbd> still walks history       | Something sourced *after* our line rebinds the arrows | `bind -q history-search-backward` shows the current binding; move the source line later in `~/.bashrc`               |
| Passphrase asked in every new terminal | The agent is not persisting                           | `echo $SSH_AUTH_SOCK` in two terminals — if it differs, something else is setting it; `JB_SSH_AGENT=0` to stand down |
| Prompt is slow                         | `git diff` on a very large repo                       | `JB_PROMPT_GIT=0`                                                                                                    |
| `[x1]` instead of `[✗1]`               | Locale is not UTF-8                                   | Intentional — the mark degrades rather than producing mojibake                                                       |
| `ssh host CMD` can't find a tool       | That shell reads no rc file                           | `ssh host -t bash -lc '…'`                                                                                           |
| Login is slower than it was            | `ssh-add` is prompting, or a slow drop-in             | `JB_SSH_AUTOADD=0` to test; then bisect `bashrc.d/`                                                                  |

______________________________________________________________________

## Uninstalling

```bash
# 1. remove the two source lines
jbx just-bashit:file remove-line \
  'if [ -r "$HOME/.config/just-bashit/bashrc.sh" ]; then . "$HOME/.config/just-bashit/bashrc.sh"; fi' \
  ~/.bashrc

# 2. and the files, if you want them gone
rm -rf ~/.config/just-bashit
```

Or open `~/.bashrc` and `~/.profile` and delete the lines by hand — there are
only two, and they are commented. Nothing else was modified, so there is
nothing else to undo.

______________________________________________________________________

## See also

- [`setup-system`](../setup-system.md) — the full flag and step reference
- [Templates](../templates.md) — reading the two shell templates on their own
- [`install-deps`](../install-deps.md) — the `deps` step, and the `jb.toml`
    package format
- [`just-runit`](../just-runit.md) — how `jbx` fetches and runs a script
