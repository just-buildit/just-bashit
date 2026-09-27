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
