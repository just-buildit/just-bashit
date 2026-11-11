# jbx-shell

Source: `src/just_bashit/jbx-shell.sh`

Apply what a `setup-system` run changed to the shell that ran it, instead of
ending with "open a new shell".

No child process can change its parent's environment, and `jbx` runs
`setup-system` as a child. A shell **function** runs in the caller's shell,
so it can source what the child wrote. This library defines `jbx` as that
function.

It is plain POSIX sh, so it works the same in bash, zsh, dash and busybox
`ash`. fish is not covered: it cannot source POSIX sh, and a fish-default
distro (CachyOS) is left for bash before `jbx` runs.

______________________________________________________________________

## jbx

```bash
. ~/.config/just-bashit/jbx-shell.sh
jbx setup-system      # jbx: applied to this shell: profile.sh bashrc.sh
```

It runs the real `jbx` with `JB_CALLER_APPLIES=1` and `JB_RELOAD_MARKER`
(the marker's path) exported. When that run changed something a shell reads
at startup, `setup-system` -- or any other script jbx ran -- appends to the
marker what to apply, one directive per line:

| Directive      | Applied as                                                |
| -------------- | --------------------------------------------------------- |
| `profile FILE` | sourced, in every shell                                   |
| `bashrc FILE`  | sourced when the shell is bash (`bashrc.sh` is bash-only) |
| `path DIR`     | put first on `PATH`, once                                 |

`profile` and `bashrc` name only just-bashit's own files. They are written
to be sourced again: `PATH` entries are added once, and a live ssh-agent is
adopted rather than a second one started. Your own `~/.profile` is never
re-run, because Debian's stock one prepends `~/bin` with no check.

The function removes any marker before the call (so one an interrupted run
left is never applied), makes its directory, and after the call applies it,
removes it and returns the run's own exit status.

A run started any other way (`bash setup-system.sh`, a script) has neither
variable, leaves no marker, and keeps the "open a new shell" hint with its
reasons.

### From your own script

Any script `jbx` runs can put a directory on the caller's `PATH` the same
way. Write `path` lines only, append rather than overwrite, and only when the
variable is set:

```bash
if [ -n "${JB_RELOAD_MARKER:-}" ]; then
	printf 'path %s\n' "${HOME}/.local/bin" >>"${JB_RELOAD_MARKER}"
else
	echo "open a new shell to use it"
fi
```

[`update-path`](../just-runit.md#update-path) does exactly this.

### From PowerShell

PowerShell's `jbx` function (from `get-jb.ps1`) sets both variables too, with
a temp file of its own as the marker. Once bash exits it puts each `path` line
on `$env:PATH`, translated by `cygpath -w` into a Windows path; `profile` and
`bashrc` lines are bash's and are ignored. It also exports `JB_CALLER=pwsh`,
and `setup-system` gives it advice that fits a PowerShell window
([closing advice](../setup-system.md#the-closing-advice)). A PowerShell script
jbx runs in the session sets `$env:PATH` itself.

## jb_reload_marker

Print the marker's path:
`${XDG_STATE_HOME:-$HOME/.local/state}/just-bashit/reload`. The one
derivation: the `jbx` function exports it as `JB_RELOAD_MARKER`, which every
writer uses.

## Where it is installed

`get-jb.sh` installs it and sources it at once, so the first
`jbx setup-system` on a new machine needs no restart. `setup-system`'s shell
step installs it too, beside `bashrc.sh`, which sources it in every later
shell. Both use the same directory (`JB_CONFIG_DIR`, else
`$XDG_CONFIG_HOME/just-bashit`), and a test holds the two spellings equal.
