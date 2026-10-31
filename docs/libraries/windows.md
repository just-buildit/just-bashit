# windows

Source: `src/just_bashit/windows.sh`

Reach Windows programs from WSL, whether or not WSL's `PATH` names them.

Windows' directories are on a WSL shell's `PATH` only when WSL launched that
shell (and `appendWindowsPath` is on). A shell reached over ssh — Tailscale
SSH, VS Code Remote-SSH — has none of them, yet interop still works: a
Windows program runs when called by its full path. `setup-system` and
`ssh-to-windows` both find their Windows programs through this library, so
they work from an ssh'd-in session too.

______________________________________________________________________

## win-exe

Print the full path of a Windows executable, or return 1 when there is none.

```bash
. just-bashit/src/just_bashit/windows.sh

cmd="$(win-exe cmd.exe)" || { echo "no WSL interop here" >&2; exit 1; }
"${cmd}" /c 'echo %USERPROFILE%'
```

Looked up in this order:

| Where                                          | Finds                                  |
| ---------------------------------------------- | -------------------------------------- |
| `PATH`                                         | whatever the shell already resolves    |
| `<C:>/Windows/System32`                        | `cmd.exe`, `icacls.exe`, `whoami.exe`… |
| `<C:>/Windows/System32/WindowsPowerShell/v1.0` | `powershell.exe` (Windows PowerShell)  |
| `<C:>/Program Files/PowerShell/7`              | `pwsh.exe` (PowerShell 7)              |

`<C:>` is wherever the mount table says the `C:` drive is mounted, not an
assumed `/mnt/c`: `[automount] root` in `/etc/wsl.conf` moves it.
`JB_PROC_MOUNTS` points it at another mount table, which is how the test
suite fakes a Windows drive on a Linux runner.

______________________________________________________________________

## win-admin-channel

Print the ssh destination (`user@host`) of this machine's **own** Windows
sshd when WSL can reach it as an elevated admin, or return 1. An admin logged
in by key over Windows OpenSSH gets the full elevated token with no UAC
prompt, so anything that needs elevation can run over this channel with nobody
at the desktop.

```bash
. just-bashit/src/just_bashit/windows.sh

if dest="$(win-admin-channel)"; then
    ssh "${WIN_SSH_OPTS[@]}" "$dest" 'Get-Service sshd'
fi
```

The host is WSL's default gateway (NAT networking; `JB_WIN_HOST` overrides
it). It is trusted only after one round trip proves the far end's
`%COMPUTERNAME%` is this machine's and the session is elevated, so a gateway
that is some other box is never mistaken for the host. `WIN_SSH_OPTS` carries
batch mode, a connect timeout, and the key named after this host
(`~/.ssh/<hostname>`) when it exists. The channel exists once
`setup-system -s sshd` has run once: it adds the firewall rule that admits
WSL.

______________________________________________________________________

## win-elevated

Return 0 when this process's Windows token is elevated — an admin
PowerShell, or a shell started from one — and 1 otherwise or when there is no
Windows to ask. A Windows program started from here inherits that token, so
an elevated step can run directly, with no UAC prompt.

```bash
. just-bashit/src/just_bashit/windows.sh

if win-elevated; then echo "admin: no prompt needed"; fi
```

It asks PowerShell `WIN_ELEVATED_PS`, the one elevation check:
`whoami.exe /groups` lists S-1-16-12288, the High Mandatory Level SID.
`win-admin-channel` asks the far end the same expression. `whoami.exe` is
named by its full path, because a PowerShell started from Git Bash inherits
Git's `PATH`, whose own `whoami` refuses `/groups`. `JB_WIN_ELEVATED=1` or
`0` answers instead, for a test.

______________________________________________________________________

## win-admin-route

How a step that needs admin runs on this machine, printed as one word (and
a destination); the first that applies wins:

| Prints     | When                                      | The step                      |
| ---------- | ----------------------------------------- | ----------------------------- |
| `elevated` | `win-elevated`                            | runs directly, no prompt      |
| `ssh DEST` | `win-admin-channel` finds one             | runs over ssh, no prompt      |
| `skip`     | the argument is 1 (`--yes`: never prompt) | is skipped, `WIN_NEEDS_ADMIN` |
| `uac`      | otherwise                                 | raises one UAC prompt         |

```bash
. just-bashit/src/just_bashit/windows.sh

IFS=' ' read -r how dest <<<"$(win-admin-route "${ASSUME_YES}")"
```

`setup-system`'s sshd step and `install-deps`' Visual Studio modify both take
it, so `--yes` means the same in both. Only the step that needs admin runs
elevated: relaunching a whole run elevated leaves files in the user's profile
owned by Administrators, which git's `safe.directory` and `~/.ssh`'s ACLs
refuse.
