# Templates

Source: `src/function-template.sh`, `src/script-template`,
`src/bashrc-template.sh`, `src/profile-template.sh`

Copy-paste starting points for new bash functions and scripts, plus the
opinionated shell configuration [`setup-system`](setup-system.md) installs.
Take only what you need.

______________________________________________________________________

## full-on-template

A complete function template demonstrating every common pattern:
getopts-based option parsing, a heredoc help string, variable initialization
before and after `getopts`, and a nested helper function.

```bash
. just-bashit/src/function-template.sh

full-on-template -h  # show usage
full-on-template -p myvalue arg1 arg2
```

Use this when your function needs multiple options, some with arguments.

______________________________________________________________________

## minimalist-template

A stripped-down function template for simple functions that don't need the
full getopts machinery.

```bash
. just-bashit/src/function-template.sh

minimalist-template -h
minimalist-template arg1
```

Use this as a starting point and add complexity only as needed.

______________________________________________________________________

## script-template

An executable script template (not a library) demonstrating:

- Bash strict mode: `set -euo pipefail`
- `IFS` configuration
- `EXIT` trap for cleanup
- `getopts`-based option parsing

```bash
# Copy and rename
cp just-bashit/src/script-template my-script
chmod +x my-script
./my-script -h
```

The template is intentionally self-contained — it does not source any
just-bashit libraries, so it works as a standalone starting point.

______________________________________________________________________

## bashrc-template

The interactive half of a cross-distro bash configuration: up/down arrow
history search, history hygiene, shell options guarded for bash 3.2, colour
and safety aliases probed rather than assumed, a git-aware prompt, ssh key
loading, and a bash-completion loader that knows where five different
distros put it.

```bash
# read it
jbx setup-system --template

# or install it, source line and all
jbx setup-system -s shell
```

Every section has an opt-out variable — see
[setup-system](setup-system.md#opt-outs) for the full list, and for why the
configuration is split across two files.

______________________________________________________________________

## profile-template

The environment half: XDG directories, `PATH`, `EDITOR`/`PAGER`, and an
ssh-agent that adopts an inherited one before starting its own. Written in
POSIX sh, because `~/.profile` is also read by dash.

```bash
jbx setup-system --template-profile
```

Exports live here rather than in `bashrc-template.sh` so that
non-interactive shells — `ssh host git push`, cron, CI — see them too.
