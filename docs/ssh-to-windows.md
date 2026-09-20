# ssh-to-windows

Publish WSL2's ssh keys to Windows, with the NTFS ACLs Windows OpenSSH
insists on.

```bash
jb-ssh-to-windows            # publish every private key in ~/.ssh
jb-ssh-to-windows --dry-run  # show what would happen, change nothing
```

The script is `src/just_bashit/ssh-to-windows.sh`; it needs nothing but
bash and a WSL2 distro with Windows interop enabled.

## The problem it solves

You have a working ssh key in WSL. `ssh -T git@github.com` authenticates from
the WSL shell. Then you try to use the same account from Windows — `git.exe`,
VS Code, a PowerShell prompt — and it fails. So you copy the key across:

```bash
cp ~/.ssh/id_ed25519 /mnt/c/Users/you/.ssh/
```

and Windows answers:

```text
Permissions for 'C:\Users\you\.ssh\id_ed25519' are too open.
It is required that your private key files are NOT accessible by others.
```

The obvious next move is `chmod 600`, and it does nothing. **`~/.ssh` in WSL is
on a Linux filesystem, where mode bits are real. `%USERPROFILE%\.ssh` is on
NTFS, where Windows OpenSSH ignores mode bits entirely and reads the ACL.** The
copied file inherited the user profile's ACL, which grants more than the owner,
and no chmod sweep can express the fix. Repairing it needs `icacls`.

That is the whole gap. `jb setup-system`'s ssh step hardens `~/.ssh` with
`chmod` and says so plainly — it is a documented no-op on Windows and MSYS2 for
exactly this reason. This tool is the other half.

## What it does

1. Resolves `%USERPROFILE%` by **asking Windows** (`cmd.exe /c echo %USERPROFILE%`), never by assembling `C:\Users\$USER`. On a domain-joined
    machine the profile is frequently neither.
1. Creates `%USERPROFILE%\.ssh` if missing and strips its inherited ACEs,
    granting only the current user — inheritably, so keys copied in afterwards
    are born correct.
1. Copies each **private key** from `~/.ssh`, plus its `.pub` when present.
1. Re-applies the per-key ACL on every run.

A private key is identified by its `-----BEGIN ... PRIVATE KEY-----` header,
not by its name. A key called `work-laptop` is published; `known_hosts` and
`config` never are, whatever they are called.

### One direction only

WSL to Windows. It never reads a Windows key back over a Linux one, and it
never modifies `~/.ssh` in the distro.

### Idempotent, and that matters here

Re-running is how you repair drift, not a mistake. Identical files are left
alone — but **the ACL is re-applied even when the bytes are unchanged**,
because the copy is not what rots. A profile-wide permissions change, a restore
from backup, or a file recreated by another tool all leave the contents correct
and the ACL wrong. That is precisely the state that reads as *"the key stopped
working and I changed nothing"*.

## Options

| Option              | Effect                                                    |
| ------------------- | --------------------------------------------------------- |
| `-h` / `--help`     | Show usage and exit.                                      |
| `-n` / `--dry-run`  | Print every copy and every `icacls` call; change nothing. |
| `-v` / `--verbose`  | Name every file, not just the ones that changed.          |
| `-f` / `--force`    | Replace a Windows key whose contents differ.              |
| `-k` / `--key NAME` | Publish only `~/.ssh/NAME` (and `NAME.pub`).              |

## Exit status

| Code | Meaning                                            |
| ---- | -------------------------------------------------- |
| `0`  | Keys are published and their ACLs are correct.     |
| `1`  | An error — including "not running under WSL".      |
| `2`  | A Windows key differs and `--force` was not given. |

`2` is deliberately not `1`: a key you have edited on the Windows side is a
decision to make, not a failure to fix. Nothing is overwritten until you say so.

!!! warning "This copies private keys"

    A second copy of a private key is a second thing to protect and a second
    thing to rotate. It is the right trade for a machine you already trust with
    both halves — you are running Windows and WSL as the same person — and the
    wrong one for a shared box.

    If you would rather keep exactly one copy, forward the agent instead:
    [`npiperelay`](https://github.com/jstarks/npiperelay) with
    `wsl-ssh-agent` lets Windows and WSL share one agent socket. That is a
    different tool with different setup costs; this one trades a duplicated
    key for having nothing to run in the background.

!!! note "Not running under WSL is an error, not a skip"

    The script is asked for by name, so a machine that cannot run it is a
    mistake worth hearing about rather than a silent success. A caller that
    wants it optional can test `/proc/version` itself.

## Verifying it worked

From Windows, not from WSL — the whole point is the Windows side:

```powershell
icacls $HOME\.ssh\id_ed25519     # expect exactly one principal, no (I) entries
ssh -T git@github.com
```
