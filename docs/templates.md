# Templates

Source: `src/just_bashit/function-template.sh`, `src/just_bashit/script-template`,
`src/just_bashit/bashrc-template.sh`, `src/just_bashit/profile-template.sh`,
`src/just_bashit/profile-template.ps1`

Copy-paste starting points for new bash functions and scripts, plus the
opinionated shell configuration [`setup-system`](setup-system.md) installs.
Take only what you need.

______________________________________________________________________

## full-on-template

A complete function template demonstrating every common pattern:
getopts-based option parsing, a heredoc help string, variable initialization
before and after `getopts`, and a nested helper function.

```bash
. just-bashit/src/just_bashit/function-template.sh

full-on-template -h  # show usage
full-on-template -p myvalue arg1 arg2
```

Use this when your function needs multiple options, some with arguments.

______________________________________________________________________

## minimalist-template

A stripped-down function template for simple functions that don't need the
full getopts machinery.

```bash
. just-bashit/src/just_bashit/function-template.sh

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
cp just-bashit/src/just_bashit/script-template my-script
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

Exports live here rather than in `bashrc-template.sh` so that the whole login
session inherits them, not just interactive terminals.

______________________________________________________________________

## profile-template.ps1

The PowerShell half. `bashrc-template.sh` makes bash behave; this makes
`pwsh` behave the same way, so moving between WSL and Windows on one machine
does not mean holding two sets of key bindings in your head.

```powershell
Copy-Item profile-template.ps1 $PROFILE.CurrentUserAllHosts
```

**The headline is Up/Down.** In bash, `history-search-backward` on the arrow
keys means typing a prefix and pressing Up walks only the commands that
*start* with it. PowerShell walks the whole history instead, ignoring what you
typed — the biggest day-to-day difference between the two shells. PSReadLine
can do exactly what bash does; it simply is not wired that way by default.

Alongside it: 100,000 lines of de-duplicated history saved incrementally (the
same three decisions as `HISTSIZE`/`erasedups`/`histappend`), `Tab` menu
completion, `Ctrl-D` to exit on an empty line, and inline history predictions
where the host supports them.

`Ctrl-Left`/`Right`, `Home`/`End` and `Ctrl-U`/`K` already match bash in
PSReadLine's defaults and are deliberately **not** re-bound — a binding
restated is a binding that can drift from the default it was copying.

!!! warning "`$PROFILE` may live in OneDrive"

    With OneDrive's Known Folder Move enabled — the default on many Windows
    installs — `Documents` is redirected and `$PROFILE` resolves to something
    like `C:\Users\you\OneDrive\Documents\PowerShell\profile.ps1`. Your
    profile then syncs between machines outside whatever version control you
    chose. Run `$PROFILE.CurrentUserAllHosts` to see where yours actually is
    before editing anything.

!!! note "Nothing here is load-bearing"

    A profile that throws paints a red wall over every new session, so every
    block is guarded: no PSReadLine, or one too old, leaves a plain shell
    rather than a broken one. Inline predictions additionally need a console
    with virtual-terminal support — a *host* fact no version check can see —
    so they are attempted and dropped rather than tested for.
