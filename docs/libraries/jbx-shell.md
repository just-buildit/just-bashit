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

It runs the real `jbx` with `JB_CALLER_APPLIES=1` exported. When that run
changed something a shell reads at startup, `setup-system` leaves a marker
listing what to apply, one directive per line:

| Directive      | Applied as                                                |
| -------------- | --------------------------------------------------------- |
| `profile FILE` | sourced, in every shell                                   |
| `bashrc FILE`  | sourced when the shell is bash (`bashrc.sh` is bash-only) |
| `path DIR`     | put first on `PATH`, once                                 |

Only just-bashit's own files are named. They are written to be sourced
again: `PATH` entries are added once, and a live ssh-agent is adopted rather
than a second one started. Your own `~/.profile` is never re-run, because
Debian's stock one prepends `~/bin` with no check.

The function returns the run's own exit status, and removes the marker.

A run started any other way (`bash setup-system.sh`, a script) exports no
`JB_CALLER_APPLIES`, leaves no marker, and keeps the "open a new shell" hint
with its reasons. So a stale marker is never applied to some later shell.

## jb_reload_marker

Print the marker's path:
`${XDG_STATE_HOME:-$HOME/.local/state}/just-bashit/reload`. Both sides of
the handshake call it: `setup-system` to write the marker, `jbx` to read it.

## Where it is installed

`get-jb.sh` installs it and sources it at once, so the first
`jbx setup-system` on a new machine needs no restart. `setup-system`'s shell
step installs it too, beside `bashrc.sh`, which sources it in every later
shell. Both use the same directory (`JB_CONFIG_DIR`, else
`$XDG_CONFIG_HOME/just-bashit`), and a test holds the two spellings equal.
