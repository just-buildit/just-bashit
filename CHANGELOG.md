# Changelog

## [Unreleased]

### Added

- **On Windows `setup-system -y` never waits on a UAC prompt, and an
    admin shell needs none (#184).** The sshd step and install-deps'
    Visual Studio `setup.exe modify` now elevate by one ladder,
    `win-admin-route` in `windows.sh`: directly when this shell is already
    elevated (`win-elevated`, the same High Mandatory Level check the admin
    ssh channel makes, now one `WIN_ELEVATED_PS` expression), over the admin
    ssh channel when there is one, and otherwise through one UAC prompt --
    except under `--yes`, which skips the step, `skipped (needs admin --   re-run from an admin PowerShell)`. install-deps takes `-y/--yes` too, and
    setup-system passes it on. The dry run says which it would be. The run
    itself is never relaunched elevated, which would leave Administrators
    owning files in the user's profile. The elevation check names
    `whoami.exe` by full path: from Git Bash, PowerShell found Git's own
    `whoami`, which refuses `/groups`.

- **`get-jb.ps1`: jbx on native Windows from PowerShell, with no bash
    window (#172).** `irm https://just-buildit.github.io/get-jb.ps1 | iex`
    in Windows PowerShell 5.1 or pwsh 7 finds Git for Windows' `bash.exe`
    (never the WSL launcher; `Git.Git` via winget when there is none),
    installs uv with winget (`astral-sh.uv`, native on ARM64) when absent,
    runs `get-jb.sh` in that bash, and writes `jbx` and `just-runit`
    functions into a marked, idempotent block of both editions' profiles
    (`JB_PS_PROFILE` overrides). The functions pass arguments through the
    environment rather than bash's command line, which MSYS would glob and
    re-quote, and forward stdin and the exit code. Windows CI runs it from
    pwsh.

- **`setup-system -s certs` puts Windows' trusted roots into WSL.** An
    opt-in step, like `sshd`: a default run does not touch the trust store.
    It exports `Cert:\LocalMachine\Root` and `Cert:\CurrentUser\Root`
    through `powershell.exe`, writes each root once as its own
    `jb-windows-root-<thumbprint>.crt` in the distro's anchor directory
    (Debian/Ubuntu/Alpine, Fedora/RHEL, Arch, openSUSE) and runs its updater,
    so a corporate TLS-inspection root that Windows trusts is trusted by
    `curl`, `git` and Python too. A root Windows no longer exports is
    removed; an unchanged export writes nothing; a failed update puts the
    previous roots back. On WSL the bash profile also points an unset
    `SSL_CERT_FILE` at the system bundle.

- **`setup-system`'s native Windows baseline installs the MSVC Build
    Tools' C++ workload (#67).** clang-cl links against the MSVC libraries
    and the Windows SDK, which `Microsoft.VisualStudio.BuildTools` provides
    only as a workload: the bare id installs the installer shell alone. A
    winget package may now name what it provides in a table keyed by its id,
    `vs_requires = [...]`. That list replaces the `winget list` probe with
    `vswhere -requires`, and is what both installs `--add`: a fresh install
    gets `winget install --override`, a shell without the workload gets the
    VS Installer's `setup.exe modify`, elevated, and a run that finds the
    workload does nothing. After an install the probe runs again and decides
    the outcome: an install that exits 0 without the workload fails, and one
    that provides it succeeds whatever its code. 3010 or a winget reboot
    HRESULT is reported as "reboot required", and any other code is named.

### Fixed

- **setup-system's `claude` step installs Claude Code on native Windows
    (#189).** It ran Anthropic's `install.sh` everywhere, which refuses a
    MINGW/MSYS/CYGWIN `uname` ("Windows is not supported by this script"),
    so the step always failed there unless `claude` was already installed.
    On native Windows it now installs through winget
    (`Anthropic.ClaudeCode`), which picks the machine's native build, and
    puts winget's Links directory on the run's `PATH` and in the closing
    advice, as uv's install does. When winget is absent or fails it runs
    `install.ps1` through Windows PowerShell, with `PROCESSOR_ARCHITECTURE`
    set for that one process from `windows-sshd.ps1`'s `Get-MachineArch`,
    so an emulated x64 shell on ARM64 still gets the arm64 build. pkg.sh's
    `_winget_portable`, `_winget_install_line` and `_cmd_dir_in` are the
    winget half of `install-uv`, now shared with this step, and
    `_ps_literal` moved to pkg.sh beside `_powershell_bin`.

- **clang-cl on native Windows is the Build Tools' clang component, so a
    Developer PowerShell finds it (#181).** `LLVM.LLVM` installed
    `C:\Program Files\LLVM\bin\clang-cl.exe` and added that directory to
    no PATH, Machine or User, so nothing could find it. The winget baseline
    drops it and asks `Microsoft.VisualStudio.BuildTools` for
    `Microsoft.VisualStudio.Component.VC.Llvm.Clang` beside the C++
    workload, through the existing `vs_requires` probe (#67): a Build Tools
    install with the workload but not the component is modified, elevated,
    to add it. The component ships x64 and ARM64 clang-cl and a
    `vsdevcmd\ext\clang_cl.bat` hook that puts the host's on PATH in a
    Developer PowerShell or Command Prompt. `vs_requires` takes component
    ids as well as workload ids; its refusal now says so.

- **`setup-system` from PowerShell no longer says `exec bash -l`, and its
    installed report on Windows lists what the winget baseline installs
    (#179, #180).** get-jb.ps1's `jbx`/`just-runit` functions export
    `JB_CALLER=pwsh`. Under it the bash reload reasons are dropped (every
    call starts a fresh login bash), and the run ends with "open a new
    PowerShell window" only when an install put a directory on the Windows
    PATH that the window predates. The installed report's rows now come from
    the `deps` baseline for this machine's package manager -- the package's
    own name, its table's new `provides` list, or each `vs_requires` id by
    install-deps' vswhere probe (now in pkg.sh, shared) -- so Windows is
    asked about cmake, clang-cl and the C++ workload, not make, cc and
    pkg-config. On native Windows the report also searches the registry's
    Machine and User PATH, so a tool installed this run is reported where it
    is instead of as missing, and the closing advice names the directory.
    A test fails on a baseline package the report could not probe for.
    On macOS with no `timeout` (the stock install) every report row read
    "does not run": bash 3.2 refused the empty command prefix; fixed.

- **ARM64 Windows gets the native uv, and the native PowerShell MSI, even
    from an emulated x64 shell (#171).** From x64 Git Bash every signal says
    x64: `uname -m`, `PROCESSOR_ARCHITECTURE`, even `OSArchitecture` in a
    `powershell.exe` it starts. astral's `install.sh` reads only `uname -m`,
    so `get-jb.sh` and `setup-system`'s `tools` step installed an x86_64 uv
    that then ran emulated. They now share one installer with jbx's Python
    runner: `pkg.sh`'s new `install-uv`. On Windows it uses winget
    (`astral-sh.uv`), which picks the machine's build. Everywhere else, and
    when winget is missing or fails, it falls back to `install.sh`. Both
    callers put winget's Links directory on the running shell's PATH,
    because winget adds it only to the user PATH. `get-jb.sh` sets it
    directly; `setup-system` sets it for the rest of the run and hands it
    to the `jbx` shell function. `windows-sshd.ps1` now reads the
    machine's architecture from the registry
    (`Session Manager\Environment`), which reports ARM64 even to an
    emulated process. It falls back to the environment variables only when
    that read fails. `_winget_installed` and the shared winget install flags
    moved from `install-deps.sh` into `pkg.sh`, so both installers use the
    same copy.

- **`setup-system -s sshd` refuses clearly when Windows has a reboot
    pending (#166).** With the servicing stack waiting on a reboot, the
    OpenSSH capability install failed with a raw `Add-WindowsCapability   failed. Error code = 0x800f0950` and the summary said only "see the log
    above". `windows-sshd.ps1` now checks Component Based Servicing's
    `RebootPending` and `RebootInProgress` before installing, stops before
    changing anything, and says to reboot Windows and re-run; setup-system's
    summary names the reason, over ssh or through UAC. An sshd already
    installed is not blocked, and Windows Update's `RebootRequired` and
    `PendingFileRenameOperations` (often full of harmless temp-file
    deletions) are not counted.

- **`setup-system -s sshd`'s WSL firewall rule survives a reboot (#80).**
    `jb-sshd-wsl` was scoped with `-InterfaceAlias 'vEthernet (WSL*'`, which
    Windows stores as the adapter's GUID, and WSL rebuilds that adapter with
    a new GUID on every boot: after the first reboot the rule admitted
    nothing and `win-admin-channel` timed out. `windows-sshd.ps1` now
    registers a SYSTEM scheduled task, `\just-bashit\jb-sshd-wsl-rescope`,
    that re-scopes the rule to the live adapter when Hyper-V's vmswitch logs
    event 9 (WSL's switch initialised) and at startup. It runs a copy of the
    script kept in `%ProgramData%\just-bashit`, writable only by
    administrators, through the same function the setup run uses; a re-run
    replaces the task rather than adding one. `windows-sshd.ps1   -CheckWslRule` reports, unelevated, whether the rule matches the live
    adapter; docs/setup-system.md has a one-line check to run after a
    reboot.

- **A failed `aliases.toml` fetch is refused, not read as "not listed"
    (#164).** jbx resolved a bare name by fetching the namespace's
    `aliases.toml`, and on any failure fell through to probing `NAME.sh` at
    the base: a transient blip sent `jbx install-deps` to the org root's copy
    of `install-deps.sh`, run without its libraries ("toml.sh: No such
    file"). The fetch now retries as every other fetch does, then refuses,
    naming the URL and curl's message. It uses `--fail`, so an HTTP error
    page is refused rather than cached, and a response with no `[aliases]`
    table is refused too. A cached copy past its TTL answers when the
    refetch fails, with a warning; under `-r` or `-n` the failure is
    refused. A just-bashit script fetched from the org root that sources its
    sibling libraries is run through the co-fetch from `jbs/`. `get-jb.sh`
    no longer installs an HTTP error page as jbx.

- **`jbx -l` reads a function whose body ends `[[ ... ]]`.** The reader that
    lists functions without running the script took the newline after a
    closing `]]` as part of the test rather than the end of the command, so
    the next line's `}` read as an argument and the function never closed:
    `jbx -l` refused the script, "unterminated at end of file". Only a
    newline inside an open `[[ ]]` now continues it.

- **`jbx SPEC FUNCTION` runs the script's top level once, not twice (#141).**
    It sourced the script in a separate child only to check that FUNCTION
    exists, then sourced it again to call it. One child now sources it,
    checks, and calls. A FUNCTION the script does not define exits 127 (was
    1), still naming it.

- **`jbx -l` runs nothing from the script (#143).** It sourced the script to
    list its functions, so a top-level `X=$(cmd)` ran `cmd`, and so did the
    top level of every library the script sources. It now reads the script
    with the lexer that used to gate it, and the files it sources the same
    way, found by their path as written: a literal path as is, a path built
    from an expansion (`"${_SCRIPT_DIR}/toml.sh"`) by its last component
    beside the script, where jbx co-fetches just-bashit's. One it cannot
    find is named on stderr. Since nothing runs, `-l` no longer refuses a
    script without a main guard: `jbx -l setup-system` lists its functions.
    An empty array (`_R=()`) no longer hides the function on the next line.

- **`deploy-docs` no longer fails on a pure version-bump commit (#151).** A
    release PR runs no test matrix, so it uploads no `test-report-xml`, and
    the step that reused the PR run's reports failed the download, so the
    run went red and the docs site's test-report and coverage pages were
    not republished for the release commit.
    `scripts/docs-reports.sh` now falls back to the newest successful `main`
    run that kept the reports, and when none did, deploys without them with
    a `::warning::`. Only an API error fails the step.

- **The test suite no longer reaches the network (#147).** Six
    `network.bats` tests probed live example.com, pypi.org and google.com,
    so a 503 from a third party's CDN turned an unrelated PR red; one
    `fetch.bats` and four `runner-names.bats` tests fetched from
    just-buildit.github.io, hidden locally by a warm `~/.cache`. Each is now
    answered by a fake curl, wget or ping, so the 200, 503, hang and
    missing-tool cases are all asserted deterministically. The gate is
    `test/setup_suite.bash`: it puts a trap curl, wget and ping first on
    PATH for every test, fences git to `file://`, starts the cache cold,
    and fails `make test` naming any test that asks for a remote host --
    even one whose own assertions pass.

## [0.11.0] - 2026-10-27

### Added

- **`jbx just-makeit:NAME` resolves against the just-makeit site.** A new
    built-in namespace rooted at `https://just-buildit.github.io/just-makeit`,
    resolved like the default one: its `aliases.toml`, then a direct
    `NAME.sh` / `NAME.py` probe. The built-in namespaces are now one table
    that the resolver, the unknown-namespace error and `-h` all read.

## [0.10.0] - 2026-10-26

### Added

- **`jbx --no-verify` skips TLS certificate checks on jbx's own downloads.**
    This is for networks whose proxy re-signs TLS with a CA the box does not
    trust, where every fetch failed with a certificate error. It reaches
    every curl call jbx makes: the script, the `aliases.toml` lookup, the
    just-bashit co-fetch bundle, the bare-name probe and the nested uv
    install. `just-runit install --no-verify` passes it to every tool it
    fetches. It is long-only, because `-k` is the checksum. It is read only
    before SPEC, so a script's own `--no-verify` argument still reaches the
    script. It warns on every run, and pairs with `-k HASH`.
- **jbx runs a script by its path in a repository, on any forge (#136).**
    `[FORGE+]https://HOST[:PORT]/PROJECT//PATH[@REF]` replaces spelling out
    each host's raw-content URL. `//` separates the repository from the
    path, and `REF` defaults to the repository's default branch. github.com,
    gitlab.com, codeberg.org and bitbucket.org are known. Any other host
    names its forge (`github+`, `gitlab+`, `gitea+`/`forgejo+`), so
    self-hosted Gitea, GitLab and GitHub Enterprise work, ports included.
    Each raw layout was measured against live repositories. The SPEC
    resolves to the raw URL and is then fetched as before, so caching,
    `-k`, `-n` and argument forwarding are unchanged. HTTP, SSH, credentials
    in the URL and unknown hosts are refused, each with an explicit error.

### Fixed

- **`jbx -l` lists a script whatever the caller's shell environment
    (#121 follow-up).** The child that sources the script inherited two
    things from the caller. Through an exported `SHELLOPTS` it got jbx's own
    `set -euo pipefail`, and `compgen -A function` returns 1 while no
    function exists yet, so the child died on its first line. Through
    `BASH_ENV` it got kcov's tracer, whose `PS4` names `BASH_SOURCE`, and a
    script with `set -u` made the next traced line fail. `make coverage`
    went red on main while `make test` passed. The child now runs without
    either, from bash's defaults.

- **`CI passed` waits for `coverage`.** A red `coverage` merged #142,
    because the one required check did not wait for it. `make   workflow-check` now fails on any pull-request job that `CI passed` does
    not wait for, unless the job runs after it.

- **Getting Started installs `jbx` (#116).** Its Installation section only
    offered the release tarball, so a reader who started there never got the
    one-line `get-jb.sh` installer every adopter points at. It now leads with
    that line and links Getting just-runit for the details. The tarball route
    stays for sourcing the libraries, and its instructions were wrong: the
    tarball has no top-level directory and no README, and its libraries are
    under `src/just_bashit/`. It now extracts into `just-bashit/`, the path
    every example in the docs sources from.

- **`jbx -n` leaves the cache untouched for just-bashit scripts and
    aliases (#122).** A `just-bashit:` spec, a `jbs/` URL and an alias into
    `jbs/` (`install-deps`, `setup-system`) took the co-fetch path before
    `-n` was checked, so the whole bundle was written to the cache, or a
    fresh cached one used without fetching; the aliases.toml lookup cached
    its file too, and the nested run that installs uv for a Python script
    dropped `-n`. All of them now fetch fresh into the run's temporary
    directory, removed on exit, so the bundle's libraries still resolve
    beside the script.

- **`jbx -l` no longer runs the script it lists (#121).** `-l` lists a
    shell script's functions by sourcing it in a child bash, so a script
    without a main guard ran in full -- `jbx -l setup-system` set the
    machine up. `-l` now reads the script first and refuses, naming the
    line, one whose top level runs a command; a top level of function
    definitions, assignments, `source`, `set` and the like, or work behind a
    main guard (`if [[ "${BASH_SOURCE[0]}" == "$0" ]]`, or the libraries'
    `(return 0 2>/dev/null) ||`), is still sourced and listed, library
    functions included. Python scripts are parsed, as before.

- **The tree-unchanged test gate covers every run and every outcome
    (#113).** It lived inline in `make test`'s recipe, so `make test-fast`
    and `make coverage` ran without it, and a bats failure aborted the
    recipe before the after-diff: a red run that also damaged the tree
    reported only the test failure. It is now one script,
    `scripts/tree_unchanged.sh`, wrapped around all three; it diffs after a
    failing run too and keeps that run's exit status. Its sabotage proof is
    kept as `test/tree-unchanged.bats`, and a new `BATS_ARGS` (default
    `test`) runs a subset through make:
    `make test-fast BATS_ARGS='-f deps test/setup-system.bats'`.

### Removed

- **BREAKING: `jb.toml` and `jb-deps.toml` are no longer read (#30).**
    `install-deps`, `inspect`, `setup-system` and `just-runit install` read
    them, with a warning, since 0.5.0 renamed the file to `bootstrap.toml`;
    every adopter has since renamed. A directory holding one of them and no
    `bootstrap.toml` is now refused, with one line naming the fix
    (`git mv jb.toml bootstrap.toml`), rather than treated as having no
    manifest and silently installing or reporting nothing. A
    `bootstrap.toml` beside a legacy file is read and the legacy file
    ignored; an explicit path argument is read whatever else is present.

## [0.9.0] - 2026-10-06

### Added

- **`just-runit -f SPEC`: fetch only (#117).** Resolves SPEC, caches the
    script (verifying `-k` when given), prints the cached path and exits
    without running it, so a later `jbx` of the same SPEC is a cache hit.
    `just-runit install` fetches every `[tools.*]` source this way.

### Fixed

- **`just-runit install` runs nothing (#117).** It pre-fetched each
    `[tools.*]` source by running itself with `-l`, and `-l` lists a
    script's functions by sourcing it, so every tool without a main guard
    ran, its output discarded -- `setup-system`, which this repo's own
    `bootstrap.toml` names, among them. It now fetches with the new `-f`:
    cache the script, print its path, run nothing.
- **`jbx -n <url>` runs the script (#118).** It failed "No such file or
    directory": the temp file's cleanup was an EXIT trap set inside the
    function that fetched it, which runs in a `$(...)` subshell, so the
    file was deleted as the subshell returned, before the script ran. The
    fetch now goes into a directory the main shell makes (under `$TMPDIR`)
    and removes on exit, after the script has run or the fetch has failed.
- **This repo's own `bootstrap.toml` installs (#119).** Three `[tools.*]`
    entries named `src/...` paths, which just-runit has never resolved (it
    has no local-path SPEC), so `just-runit install` here failed on all
    three. They are dropped: the Makefile runs `install-deps.sh` from
    source, and the runner and its installer are not tools this repo
    fetches. `test/runit-install.bats` now installs the file, offline.

## [0.8.0] - 2026-10-03

### Breaking

- **Native Windows builds with clang-cl; the MinGW toolchain is gone.**
    just-makeit and doppler build Windows natively with clang-cl, so
    `setup-system`'s msys2 baseline no longer carries the MinGW gcc toolchain
    -- MSYS2 is the bash host, with only the tools the scripts use. The
    winget baseline (clang-cl, CMake, Git) gains PowerShell 7, and an MSYS2
    host runs it too, so the native toolchain arrives from either bash.

### Changed

- **CI tests each tree on main once.** A PR rebased onto main's tip and
    green merges without re-running the matrix: ci.yml now asks the vendored
    `changes` workflow (canonical), and `make ci-changes-wiring-check` keeps
    every job waiting on it. Pages still deploys on such a merge, from the
    PR run's test and coverage reports. Measured before: b32288a's tree was
    PR #98's, and main re-ran all of it (windows alone 535 s).
- **Library headers no longer stamp a version.** Every `# PACKAGE:` header
    read `just-bashit version X`, so every release rewrote all 22 shipped
    files, and every repo vendoring one byte-for-byte went red on its drift
    gate with no code change (`~/.claude`'s `jbs/windows.sh` was stale on
    nothing but its version line). The header is now `# PACKAGE: just-bashit`;
    the version lives only where something reads it at runtime.
    `version-files-check` fails on a version-stamped header.

### Added

- **`jbx setup-system` applies its changes to the shell that ran it.** No
    child process can change its parent's environment, so `jbx` is now also
    a shell function (`jbx-shell.sh`, POSIX: bash, zsh, dash, busybox ash).
    It runs the real `jbx`; when setup-system changed what a shell reads at
    startup, it leaves a marker naming just-bashit's own files -- written to
    be sourced again -- and the function sources them in place, instead of
    "open a new shell". `get-jb.sh` defines it on first run and the shell
    step installs it beside `bashrc.sh`, which sources it in every later
    shell. A run started any other way writes no marker and keeps the hint.
    fish is not covered: it cannot source POSIX sh, and is left for bash
    first.
- **`setup-system` ends with what is installed, by version and path.**
    After the per-step summary, an `installed` table lists git, make, cc,
    cmake, pkg-config, curl, awk, ssh, gh, uv, pwsh (with PSScriptAnalyzer)
    and claude: each tool's own `--version` and where it runs from, or
    `missing`. ~/.local/bin is searched as well, since the run that put uv
    and claude there has not got it on PATH yet.
- **`setup-system`'s ssh step asks GitHub whether it accepts the key.**
    Whichever key the step ends with (kept, adopted from Windows, or new),
    `ssh -T git@github.com` with that key alone reports, in the summary, the
    account it authenticates as, or the `gh ssh-key add` that registers it.
    A passphrase key not in ssh-agent is reported as untestable, never as
    unregistered. Informational only: it never fails the step.
    `JB_SSH_GITHUB_CHECK=0` turns it off.

### Fixed

- **"open a new shell" only when the shell really is out of date, and why.**
    `setup-system` ended every run with it, `-s ssh` included, which changes
    nothing a running shell reads. It is now printed only when a run wrote
    (or, dry run, would write) a file the shell sources at startup, or left a
    tool in `~/.local/bin` while that is not on the caller's `PATH` -- with
    the reason beneath it. (setup-system cannot apply the change itself: it
    runs in a child process, and sourcing its strict-mode script into an
    interactive shell would close the terminal on the first error.)
- **On WSL, one ssh key per box, not per distro.** Distros do not share a
    filesystem, so every distro's ssh step generated its own key under the
    same name and comment (three different `matt@swiftgo-ultra7` keys on one
    machine). The step now keeps a key the distro already has; otherwise it
    adopts `%USERPROFILE%\.ssh\<host>` from Windows; only then generates,
    and publishes the new key to Windows (through ssh-to-windows) so the
    next distro adopts it. `win-home` in windows.sh is the one profile
    lookup, shared with ssh-to-windows.
- **The setup-system suite cannot reach the real Windows.** On a WSL box
    the real `/proc/version` made every test "on WSL", and a key test
    published its throwaway key into the developer's own `%USERPROFILE%\.ssh`.
    Each test now starts as plain Linux with no Windows on PATH and an empty
    mount table, and a test proves `win-exe cmd.exe` and `win-home` fail
    from that default.
- **The ssh key is named after the host on a machine with no `hostname`
    command.** Fedora's WSL image has none, so `setup-system`'s ssh step
    fell back to the literal `id_ed25519`, commented `matt@id_ed25519`. One
    function, `ssh-key-name` in windows.sh, now derives the name from bash's
    own `$HOSTNAME` for both the ssh step and the admin channel's key lookup,
    which carried its own copy of the same derivation.
- **The bootstrap runs on a machine with no awk.** A minimal Debian 13 WSL
    image ships none, and `jbx setup-system` -- the step that installs one --
    died resolving its own alias (`awk: command not found`). jbx's alias
    lookup, `bootstrap.toml` source list and function listing are pure bash
    now, setup-system's baseline installs awk (`mawk` on apt, `gawk` on
    pacman/dnf/zypper) for the steps after it, and a test resolves an alias
    with a PATH that holds no awk at all.
- **`get-jb.sh` no longer reports uv installed when it is not.** uv's
    installer needs awk; without one it failed its checksum and the script
    still printed "uv installed". It now skips uv with the reason when awk is
    missing, and claims success only when the binary exists.
- **Two WSL tests can no longer drive the real Windows.** "finds
    powershell.exe under the C: mount when PATH lacks it" (and its
    ssh-to-windows twin) hid a stub by moving it off PATH, assuming no
    Windows on PATH. On a real WSL box Windows' System32 is on PATH, so the
    genuine powershell.exe answered: it ran a stale launcher left in the
    Windows temp dir and raised a real UAC prompt, and approving it re-ran
    that machine's sshd setup elevated. A shared helper now takes every
    Windows drive mount off PATH and fails the test, before anything runs,
    if the program is still reachable.
- **`setup-system`'s pwsh step installs the ICU runtime, and a pwsh that
    cannot start is a failure.** The Linux tarball does not carry ICU, and
    .NET aborts without it before PowerShell reads an argument, so on a
    minimal Debian 13 the step reported `pwsh already installed (ok)` while
    every call, the PSScriptAnalyzer install included, died with
    `Couldn't find a valid ICU package`. The step now installs ICU through
    install-deps on every Linux pass (apt's versioned `libicuNN` derived
    from apt's own lists; `icu`, `libicu`, `icu-libs` on pacman, dnf, apk),
    and checks that pwsh runs rather than that it is on `PATH`.
- **`make test` initializes the bats submodules.** A plain clone left
    `test/bats` and both helpers empty, so the suite died before its first
    test; CI never saw it because its checkout recurses.
- **`make test` leaves the tree as it found it.** Its last step deleted the
    `package.json` both bats submodules track, so every run left them dirty.
    It no longer does, and `make test` now fails if a run changes the
    working tree, inside submodules included.

## [0.7.1] - 2026-10-02

### Changed

- **0.7.0 was tagged but never published; 0.7.1 is that release.** The
    canonical standard moved (just-buildit.github.io#86) while 0.7.0's
    release ran, so `standard-check` turned its commit's CI red and the
    release workflow refused to publish, correctly. 0.7.1 carries every
    0.7.0 change below plus the re-vendored `standard.mk`.

## [0.7.0] - 2026-10-02

### Fixed

- **`install-deps` bounds every apt request** (#89). `apt-get update` and
    `apt-get install` ran with no `Acquire` options, so a mirror that
    stalled mid-transfer held the caller until its CI job's ceiling (29
    minutes in just-makeit, just-makeit#1792). Both now pass
    `-o Acquire::Retries=3 -o Acquire::http::Timeout=30   -o Acquire::https::Timeout=30`, so a stall becomes an error the
    retries cover.

- **`windows-sshd.ps1` no longer prints a stray `False`.** The winget
    attempt's return value was not captured, so a first run that fell back
    to the MSI printed it (seen on swiftgo-ultra7).

- **`jbx setup-system` runs under an older `jbx`.** An installed `jbx`
    co-fetches the libraries on its own built-in list, and nothing updates
    an install, so a 0.4.1 `jbx` fetched no `windows.sh` and `setup-system`
    died sourcing it (seen on zen-ai445, #75). `setup-system` now loads its
    libraries through `_asset`, which uses the sibling copy when there is
    one and otherwise fetches it from the mirror, the way it already
    fetched `windows-sshd.ps1`.

- **The package-manager list had five copies and no gate.** `TOML_KNOWN_PMS`
    in `toml.sh` decides whether a `[group.pm]` section is recognised as a
    group at all, so a manager added to `install-deps` but not to that array
    fails with `no packages or cmd found` — a message about the manifest, for
    a bug in the code. That is how `winget` first failed here. One test now
    derives the set from that array and requires a `_do_install` arm, an
    entry in `--help`'s supported list, the `One of:` line in `get-pkg-mgr`'s
    help, a row in the docs manager table and a section in `template.toml`;
    a second fails on any `_do_install` arm the array omits. Both directions,
    one declaration.

### Added

- **Windows provisioning with no clicks after a box's first run (#76).**
    `setup-system -s sshd` now runs `windows-sshd.ps1` over an admin ssh
    session to the machine's own sshd when one exists: an admin logged in by
    key is elevated with no UAC prompt, so nobody has to be at the desktop,
    and the output streams back live. `windows.sh` gains `win-admin-channel`,
    which trusts the far end only once it has proved to be this machine and
    elevated. `windows-sshd.ps1` adds a firewall rule admitting the
    machine's own WSL (by its virtual interface), installs pwsh with winget
    and falls back to the MSI only in a first UAC-elevated run, and counts
    an `InstallPending` capability as installed. Proven on zen-ai445: the
    documented command, from a remote session, zero clicks.

- **`windows.sh`: `win-exe`, one lookup for a Windows program from WSL.**
    Windows' directories are on a WSL shell's `PATH` only when WSL launched
    that shell; one reached over ssh (Tailscale SSH, VS Code Remote-SSH) has
    none, though interop still runs a program by full path. `win-exe` tries
    `PATH`, then `System32`, Windows PowerShell and PowerShell 7 under the
    `C:` mount read from the mount table. `setup-system` had this inline;
    `ssh-to-windows` did not and died from an ssh'd-in shell (#68). Both use
    the library now, and `jbx` fetches it with them.

- **`setup-system -s sshd`: Windows' own OpenSSH server as a boot-time
    service, so a Windows machine answers ssh even when WSL is down.** Runs
    from WSL or natively under MSYS2 / Git Bash. An ssh
    server inside WSL2 dies with the VM, which stops on its own when idle or
    after a crash — the box goes dark exactly when you need it. The new step
    runs `windows-sshd.ps1` elevated (one UAC prompt): key-only, keys
    mirrored from `github.com/<user>.keys` into the file sshd actually reads
    for an admin, `pwsh.exe` as the login shell, installed from the release MSI
    at the `pwsh` step's pinned version (winget fails with access denied
    when elevated this way), the firewall limited to `--sshd-allow`, and the service set to
    start at boot. `sshd_config` edits land above the first `Match`, are
    validated with `sshd -t`, and roll back if rejected; the script refuses
    to run with no keys rather than lock the machine. Opt-in: a default run
    never opens a port.

- **`install-deps`: a `winget` section, so Windows installs rather than
    prints.** `msys2` has only ever printed a `pacman` line to run by hand,
    so nothing in this repo could provision a Windows machine. `winget` does
    install: `[runtime.winget] packages = ["Python.Python.3.13"]` installs
    Python. Names are winget **ids** — `winget search python` shows them.

    Three things follow from winget itself. It takes **one query per
    invocation**, unlike every other manager here, so a second id on the same
    line is read as an argument to the first and the install silently covers
    less than the manifest asked for — it is called once per package, and a
    test counts `--id` per line. An id `winget list` already finds is
    **skipped**, which is what makes re-running a manifest a no-op; the probe
    reads `list`'s 0 / non-zero rather than the install's exit code, because
    winget returns HRESULTs and a shell sees only the low byte — an absent
    package's `0x8A150014` arrives as plain `20`. And it gets **no `sudo`**:
    there is none on that side, and from WSL a prefix would only run the
    interop call as Linux root.

    **winget ignores `http_proxy`** — it fetches through WinHTTP and takes the
    system proxy. Its own `--proxy` is refused until an administrator runs
    `winget settings --enable ProxyCommandLineOptions`, so a configured proxy
    is reported rather than passed as a flag that would fail on a stock
    machine. Measured 2026-09-20 against winget v1.29.290, which exits 2 with
    exactly that sentence.

    Detection: `pacman` decides. MSYS2 and Git Bash report the same `uname`,
    so `uname` alone cannot separate them. MSYS2 has `pacman` and keeps
    `msys2`; **Git Bash has none and was being handed a `pacman` line it
    could not run**, so it now gets `winget`. `get-pkg-version winget` reads
    the version beside the matching id — the Name column holds spaces, so it
    is not a fixed field number, and `winget.exe` writes CRLF.

- **`setup-system`: the `deps` step installs a baseline toolchain.** It
    used to read only a `bootstrap.toml` in the current directory, so the
    fresh-machine run — from `$HOME`, where there is none — installed no
    packages, and the first C build on a new box failed with no compiler.
    `deps` now always installs a C compiler, `make`, `cmake`, `pkg-config`,
    `git`, `curl`, `tar` and ssh for the detected package manager, then a
    project's `bootstrap.toml` as before. On winget (Git Bash, #60) the
    baseline is CMake, Git and LLVM (clang-cl); the MSVC Build Tools'
    C++ workload needs an installer override winget packages cannot carry
    yet (#67). The baseline is a manifest in
    `bootstrap.toml`'s own format, handed to the same `install-deps` call, and
    embedded in the script because the jbs mirror serves only `*.sh`. A test
    reads the manager list from `install-deps`' own dispatch and fails on any
    manager without a baseline.

- **`workflow-check`: `gates-home-check`, one level up.** `gates-home-check`
    asks whether every gate is reached by a CI target. Nothing asked the same
    of the workflow itself, and the gap shipped: `deploy-docs` downloaded
    `test-report-xml` while declaring only `needs: [coverage, lint]`, so it
    consumed an artifact from a job it never waited for. It passed on timing
    until the container jobs grew slower, then turned `main` red on two
    commits whose pull requests were both green.

    Four invariants, each replayed as a test: every downloaded artifact is
    uploaded by a job in the consumer's `needs` closure (transitive waits
    count); every downloaded artifact is uploaded by *something*, since a
    renamed upload fails identically and reads the same in the log; every job
    with no pre-merge run is declared in `.github/no-pre-merge-run`; and a
    stale declaration fails, so that list may only shrink.

    It parses with `awk` rather than a YAML library so it runs in the same
    containers as the suite, which carry no Python. A parser that reads
    nothing would bless any workflow, so finding no jobs, uploads or
    downloads is an error rather than a pass.

    `deploy-docs` is the one declared entry: it publishes to Pages, which a
    pull request must not do. Its fallible half — building the site — could
    move to a PR-visible job, and until it does a broken deploy is found on
    `main` or not at all.

- **`setup-system`: a `pwsh` step.** Installs native PowerShell 7 and the
    `PSScriptAnalyzer` module, so `make lint-psscriptanalyzer` has something
    to run. Until now the analyzer gate depended on a Windows interpreter
    reached through WSL interop, which meant translating every path with
    `wslpath -w` and left a Linux-only machine with a gate that could not run
    at all.

    The architecture is DERIVED from `uname -m` — `x86_64` → `x64`,
    `aarch64`/`arm64` → `arm64`, `armv7l` → `arm32` — because these machines
    are not all x86, and a hardcoded `x64` URL fails on an arm box inside
    `tar`, with a message naming neither the architecture nor the download.
    Four tests pin a platform through `JB_UNAME_S`/`JB_UNAME_M` and assert
    the tarball that comes out; hiding `pwsh` from `PATH` instead would prove
    nothing, since `/bin` is a symlink to `/usr/bin` on Debian. The
    interpreter is named through `JB_PWSH` for the same reason, and for one
    more: GitHub's macOS and Windows images ship `pwsh`, so on those runners
    every install test would have taken the "already installed" path and
    checked nothing.

    The version is pinned in the script, so an upgrade is one you chose. The
    URL is asserted against that one declaration rather than against a copy
    in the test, which is the drift worth catching.

    macOS takes the Homebrew cask, since the tarball is a Linux build that
    would unpack into a `pwsh` that cannot execute. Windows is reported as
    `skipped`: `install-deps` has a `winget` section now (#60), and wiring
    this step through it is #59; until then there is nothing honest to do
    from here. A missing prerequisite reads as `skipped`, never
    as `failed` — only an install that was attempted and did not finish is a
    failure.

    The step list is declared in four places — the array, the string,
    `--help` and the docs table — so two tests now read the validator's own
    "known steps" list and fail on any step missing from the help text or
    from `docs/setup-system.md`.

### Changed

- **`setup-system`'s `git` step now sets a missing `user.name` /
    `user.email`.** It used to leave identity alone on principle, which left
    a fresh machine with none at all: anything deciding what a machine is for
    from `git config --global user.email` saw nothing and silently did
    nothing. An unset value now comes from `GIT_AUTHOR_NAME` /
    `GIT_AUTHOR_EMAIL`, or is asked for when stdin is a terminal and `--yes`
    was not given; with neither, the step warns and names the command. A
    value already set is never touched, and a per-repo identity still wins.

## [0.6.0] - 2026-09-09

### Fixed

- **`deploy-docs` waits for the job whose artifact it downloads.** It pulled
    `test-report-xml`, which the primary test job uploads as its last step,
    while declaring only `needs: [coverage, lint]` — consuming an artifact
    from a job it never waited for. It worked purely because the test job
    happened to finish first, and stopped when the container jobs began
    installing from `bootstrap.toml` and grew slower: `deploy-docs` then
    asked for the artifact 35 seconds before it existed, and `main` went red
    on two commits whose pull requests were both green.

    It is not the action version skew it resembles: `upload-artifact` tops
    out at v7.0.1 and `download-artifact` at v8.0.1, so that pairing is
    correct. No pull request could have caught it either — `deploy-docs` is
    gated on `refs/heads/main` and is skipped on every PR, so it has no
    pre-merge execution home at all.

### Added

- **The `ssh` step repairs a `~/.ssh` that lost its permissions, not just the
    directory.** It set `0700` on `~/.ssh` and `0600` on a key it generated
    itself, so a directory whose contents were *synced into place* kept
    whatever modes it arrived with — and `ssh` then refuses the key with
    `UNPROTECTED PRIVATE KEY FILE` without saying how to fix it.

    `jbx setup-system -s ssh` now sweeps the whole directory. This is not a
    substitute for copying properly: `rsync -a` and `tar` both carry POSIX
    modes, so a Linux-to-Linux move loses nothing. It is for the crossings
    that have nowhere to record them — a Windows filesystem under WSL (DrvFs
    reports `0777`), FAT, a zip, or a git checkout, which keeps only the exec
    bit.

    Private keys are found by their `-----BEGIN … PRIVATE KEY-----` header
    rather than by name, so a key with no matching `.pub` is still repaired.
    `config` and `authorized_keys` are covered; `*.pub` and `known_hosts` are
    left alone.

    The sweep uses `go-rwx`, so it only ever tightens: a key deliberately at
    `0400` keeps `0400` instead of gaining owner-write, and a second run
    changes nothing. It reads first lines with the `read` builtin, so it adds
    no command to the set a PATH-restricted machine needs to reach this step.

### Fixed

- **A broken third-party apt source no longer fails `install-deps`.**
    `apt-get update` exits non-zero if **any** configured source fails, and a
    CI runner carries sources the project never chose — GitHub's Ubuntu image
    ships `packages.microsoft.com`. Measured 2026-08-12 on doppler CI: the
    azure-cli and prod repos returned 403, `update` exited 100, and the matrix
    leg died **without ever attempting an install**, while the Ubuntu archive
    holding every package it actually wanted was fine. Four sibling legs on the
    same commit passed, and the leg passed on rerun — so the wrong thing was
    the gate.

    `update` now warns and names what happened; `install` is the gate. A
    package that genuinely cannot be resolved still fails, loudly and by name.

    Only the `apt` branch changes — every other package manager already
    refreshes as part of its install. Both directions are tested with a PATH
    shim, and verified by sabotage: reverting the fix turns them red.

### Changed

- **`make install-deps` runs this repo's own script instead of the published
    one.** The target fetched `install-deps.sh` from the CDN via `jbx`, while
    CI ran `src/just_bashit/install-deps.sh` — one step with two execution
    homes, in the one repo that owns the script. The version under development
    was never what ran locally, so a change could not be tried without
    releasing it first.

    `standard.mk` gained an `INSTALL_DEPS_CMD` hook upstream (defaulting to
    the existing fetch, so no other repo changes), and this repo sets it to
    the local script. CI still invokes the script directly, because the
    container jobs install `make` *from* `bootstrap.toml` and it does not
    exist yet at that point — but both callers now run the same command.

## [0.5.1] - 2026-09-08

### Added

- **`version-files-check`: a gate on the bumpversion table.** Three releases
    have now been damaged by the same class of bug — `just-runit`'s `_VERSION`
    was unregistered and sat at 0.1.4 through two releases, `make-run.sh`
    shipped in 0.4.0 with no entry, and the `jb.toml` → `bootstrap.toml`
    rename left an entry pointing at a file that no longer existed, which
    broke `make bump-version` outright. Each was found by hand, at release
    time, by someone wondering why a number was wrong.

    `version-check` cannot catch any of them: it compares the manifests to
    each other *after* a bump, so it is blind to a bump that never ran, an
    entry that quietly matched nothing, and a line it was never told about.

    The new gate checks three things — every registered `filename` exists,
    every registered `search` actually matches in its file (a search that
    matches nothing bumps *silently* and is worse than a missing entry), and
    every version-declaring **line** is covered, not merely every file. The
    line-level distinction is the whole point: `just-runit` was registered for
    its header while its `_VERSION` went unbumped, and a file-level check
    passes that green. The first draft of this gate was file-level and did
    exactly that, which is why the gate now has its own tests.

    Declarations are told from prose without an exclusion list to drift: a
    line counts only if the version is quoted, or the line matches a search
    shape already in the table. Source and docs narrate releases — `just-runit`
    itself says "This triggered on jb until 0.5.0" — and bumping those
    sentences would make them false.

    Runs in `make lint`, so it gates every PR rather than only the release.

## [0.5.0] - 2026-09-07

### Added

- **`install-deps` honours the standard proxy variables, and `--proxy URL`
    sets them.**

    Exporting `http_proxy` and running `make install-deps` appeared to be
    ignored. It was: `sudo` resets the environment, so every proxy variable
    was dropped on the far side of the escalation, and nothing the caller
    could do from their own shell would fix it.

    The assignments are now re-applied *after* the `sudo` binary rather than
    before it, surviving `env_reset` without depending on the sudoers
    `env_keep` list. Order is the whole point — `env http_proxy=… sudo   apt-get` sets the variable for `sudo` itself and has it reset away again.

    No per-manager translation was needed: apt, pacman, dnf, zypper, apk and
    brew all fetch over libcurl or read these names directly. `--proxy` sets
    `http_proxy` and `https_proxy` in both spellings, because apt, apk and
    libcurl read the lowercase names while Homebrew's Ruby reads the
    uppercase ones. `all_proxy` and `no_proxy` are only ever carried through
    from the environment: one URL says nothing about which hosts to bypass or
    how to reach a SOCKS relay, so synthesising them would be a guess.

    A `no_proxy` with no proxy beside it is left alone rather than wrapping
    every command in `env` — it describes exceptions to a configuration that
    does not exist. The variables are also exported into the script's own
    environment, so a verbatim `cmd` array inherits them without being
    rewritten.

- **`install-deps` derives whether it needs `sudo`, with `--sudo` /
    `--no-sudo` to force it.**

    The prefix was hardcoded, which made `bootstrap.toml` unusable as the
    single source of dependencies: a CI container runs as root and ships no
    `sudo` binary, so every run of the list had to be duplicated inline in
    the workflow, per distro. Both copies then drifted independently.

    A command is now prefixed only when the manager needs root, the caller is
    not already root, and `sudo` resolves on `PATH` — so the same invocation
    works on a workstation and in a root container with no flag. `brew` is
    never prefixed; Homebrew refuses to run under `sudo`. Not root and no
    `sudo` warns on stderr and runs unprivileged, letting the package manager
    report the real permission failure rather than guessing at another
    escalation tool.

    The decision is made once and read by both the executor and the
    `--dry-run` printer, so `-n` output is exactly what would have run.
    `cmd` arrays are still executed verbatim and are the one place a
    hardcoded `"sudo"` will still break a root container — the documented
    examples no longer contain one.

### Changed

- **CI installs from `bootstrap.toml` instead of repeating the package list
    per container image.** Each job now bootstraps only what
    `actions/checkout` needs — `git`, plus a TLS trust store on the images
    that ship none, plus `bash` on Alpine — and then runs `install-deps.sh`
    against the manifest. The four inline Linux lists, the macOS `brew   install` line and the coverage job's copy are gone; the dev dependency
    list now exists exactly once. Windows is the remaining carve-out:
    `msys2/setup-msys2` takes its package list as an action input, before
    checkout, so `[dev.msys2]` is still mirrored in the workflow.

- **BREAKING: `jb.toml` is now `bootstrap.toml`, and `jb` / `just-buildit` are
    no longer runner names.**

    `jb` reads as just-buildit — the PEP 517 build backend — which has never
    opened that file; it reads `pyproject.toml`, like every other backend. One
    token meant three things at once: the GitHub org, the backend, and (via a
    symlink `get-jb.sh` created) this runner.

    Naming the file after a tool was the deeper mistake, and would have been
    one without the collision: **two** different tools already read it
    (`just-runit install` takes `[tools.*]`; the package groups are read by
    `install-deps`, a separate fetched script), and the tool names were
    themselves unsettled. `bootstrap.toml` names what the file declares, which
    does not move when tools are renamed.

    Migration is `git mv jb.toml bootstrap.toml`; nothing inside changes.
    `jb.toml` and `jb-deps.toml` are still read and warn — these scripts are
    fetched live from the CDN on every CI run, so a hard cutover would break
    every repo that had not yet renamed, in the window between the publish and
    their rename. Removal is tracked separately.

- **The runner's subcommands moved to the full name.** They were only ever
    reachable under `jb` / `just-buildit`, so removing those aliases had to
    give them a home. `just-runit <subcommand>` now works and falls THROUGH to
    the SPEC runner when the first argument is not a subcommand, so
    `just-runit <url>` is unaffected. `jbx` deliberately takes no subcommands:
    that is the escape hatch that keeps a script genuinely named `install`
    reachable as `jbx install`, with no SPEC shadowed by a keyword.

    `get-jb.sh` stops creating the `jb` and `just-buildit` symlinks and prunes
    them on upgrade, alongside the existing `jr` / `jx` pruning.

### Fixed

- **`make bump-version` was broken, so no release could be cut.** The
    `jb.toml` → `bootstrap.toml` rename updated the file but not the
    `[[tool.bumpversion.files]]` entry pointing at it, so every bump died with
    `FileNotFoundError: File not found: 'jb.toml'`. Nothing caught it because
    no release had been attempted since the rename — `version-check` compares
    the manifests to each other, which cannot detect a bump that never ran.

- **`toml.sh` silently parsed a CRLF file as empty.** `read` strips the
    newline but not the carriage return, and both places that recognise a
    section header are exact matches — `[[ "$line" == "$target" ]]` in
    `toml_get_array`, and a `$`-anchored regex in `toml_discover_groups`. A
    trailing CR failed both, so every function returned success with no
    output.

    On Windows, where `actions/checkout` writes CRLF, that meant
    `install-deps` found no packages in a perfectly valid `bootstrap.toml`.
    It went unnoticed because every fixture in the suite is written with
    `printf`, so LF was the only line ending ever exercised — the bug was
    only reachable through a file that had been through a checkout, which the
    tests never used. The regression tests now build CRLF fixtures explicitly.

- **`make ship` could report a release as failed while it succeeded.**
    `release-watch` took the newest release run with `--limit 1`, but `ship`
    is `tag-release` then `release-watch`, and the tag push returns before
    GitHub has created the run — so the newest row was still the *previous*
    release. Shipping v0.4.1 watched a run that had failed the night before
    and exited 1 while the real release went on to succeed. A watcher that can
    report the wrong run is worse than no watcher, because the failure it
    invents looks exactly like a real one. It now selects the run by tag —
    `--branch "v$VERSION"`, which is what a tag-triggered run carries — and
    waits up to 60s for it to exist, erroring clearly if it never does.

- **A re-dispatched release always failed at the last step.** Since
    `gh release create` refuses an existing tag, re-driving a release that had
    already got as far as publishing died on "a release with the same tag name
    already exists" — after build and publish had both succeeded. The
    `workflow_dispatch` trigger was added to this workflow so a release could
    be re-driven through a webhook outage; a final step that cannot survive a
    second run takes that ability back. It now updates the release in place
    when one already exists.

## [0.4.1] - 2026-08-06

### Added

- **`make-run` is documented.** It shipped in 0.4.0 as the headline feature
    and appeared in no page, no nav entry, and no line of the README — so the
    one tool whose whole purpose is ending hand-transcribed commands could
    only be found by reading its source. New page under Libraries covering
    `mk-var`, `mk-vars`, `mk-run`, `mk-has` and `mk-origin`, the
    undefined-is-not-empty rule, and why the queries avoid `--eval`.

- **`docs-coverage` gate.** Two invariants, one for each way the above went
    unnoticed: every file shipped in `src/just_bashit/` must be named
    somewhere in the docs, and every page under `docs/` must be reachable
    from `zensical.toml`'s nav. `docs/changelog.md` is excluded as a mention
    source — it records every script ever added, so counting it would pass
    everything the moment it was released. Dispatched from pre-commit with
    `always_run`, so it runs inside `make lint` (which CI runs) and fires on
    commits touching no markdown, which is what adding a script looks like.

### Fixed

- **The docs pointed at `src/`, where nothing has lived since 0.2.0.**
    Scripts moved to `src/just_bashit/` for Python packaging and the docs kept
    the old path, so every `. just-bashit/src/datetime.sh` in the README, the
    getting-started guide, and all ten library pages failed for anyone who
    copied one — including from an unpacked release tarball, which carries the
    current layout.

- **The README described a package layout that no longer existed**, and never
    mentioned installation, the `jb` / `jbx` / `jb-inspect` entry points, or
    `make-run`.

## [0.4.0] - 2026-08-06

### Added

- **`make-run.sh` — ask a repo what its commands actually are.** Anything
    needing a project's command has been transcribing it by hand, and
    transcriptions drift: a skill doc said `make docs` runs
    `uv run zensical build --clean`, the sanctioned default was
    `uv run --group dev zensical build --clean --strict`, and doppler — which
    overrides `ZENSICAL` — actually runs `uv run --group docs ...`. Three
    answers, two wrong, nothing to make them disagree out loud. `mk-var`,
    `mk-vars`, `mk-run`, `mk-has` and `mk-origin` read the result of
    `standard.mk`'s defaults layered with the repo's overrides, so there is no
    second copy to vendor and nothing to keep in sync. Reachable as
    `jbx make-run` or `jbx just-bashit:make-run`.

    Two properties are pinned by tests, both so that an empty answer means
    something specific rather than nothing: an **undefined** variable is an
    error and never an empty string (`DOCS_CHECK_CMD ?=` is legitimately
    empty; a typo'd name is not), and an **unparseable** makefile fails loudly
    (`make -pRrq` exits 1 in question mode, which is normal, and 2 when it
    cannot read the makefiles at all).

### Fixed

- **CI is reachable when GitHub sheds webhooks.** `push` and `pull_request`
    are both webhook-delivered, so during the 2026-08-06 Actions incident —
    deliveries throttled to ~15% — this repo had no reachable trigger at all
    and `gh workflow run` returned 422. `workflow_dispatch` is only honoured
    when it exists on the default branch, so it could not be added from the
    branch that needed it. `ci.yml` now carries it.

- **`make-run` avoids `--eval`, which GNU make 3.81 lacks.** The option
    arrived in 3.82 and macOS still ships 3.81 as `/usr/bin/make`, so the
    first cut passed every Linux runner and failed only on macOS — confirmed
    by a real run, where exactly the `--eval` callers failed and the rest
    passed. The query now goes through a sentinel target in a throwaway
    makefile passed alongside the repo's own via `-f`.

## [0.3.2] - 2026-08-03

### Fixed

- **The bootstrap now fetches on macOS/BSD again.** `just-runit` and
    `setup-system.sh` run under a strict `IFS=$'\n\t'` (no space), then passed
    curl an *unquoted* `$(_curl_retry_opts)` of a space-joined flag string —
    which does not word-split under that IFS, so curl received the whole
    `--retry 3 --retry-connrefused --retry-all-errors` as one bogus option and
    aborted every fetch (`curl: option --retry 3 …: is unknown` → `fetch   failed`). The retry flags are now a bash array expanded
    `"${_CURL_RETRY_OPTS[@]}"`, so they split into distinct arguments regardless
    of IFS. (The EL8 path from 0.3.0 was affected identically; its test masked
    the bug by never parsing the flags.)

## [0.3.1] - 2026-08-03

### Fixed

- **The bootstrap now works on macOS/BSD, which have no `sha256sum`/`md5sum`.**
    `just-runit` hashed cache keys and verified downloads with the GNU coreutils
    names, so on macOS a fetch died with `sha256sum: command not found` and
    `jbx`/`install-deps` could not run at all. It now prefers the coreutils
    tools and falls back to `shasum -a 256` / `md5`.

## [0.3.0] - 2026-08-03

### Added

- `setup-system` tool: takes a fresh machine to a working one in one command —
    system packages (via `install-deps`), bash configuration, ssh key and agent,
    git defaults, `uv` + pre-commit, and Claude Code. Every step is idempotent
    and individually selectable with `-s` / `--skip`; `--dry-run` prints the
    whole plan without touching anything.
- `bashrc-template.sh` and `profile-template.sh`: an opinionated, cross-distro
    bash configuration. Up/down arrow history search, history hygiene, an
    ssh-agent that adopts an inherited one before starting its own, a git-aware
    prompt, probed colour aliases, and a bash-completion loader. Installed to
    `~/.config/just-bashit/` and sourced by a single line, so `~/.bashrc` stays
    the user's own file. Exports live in the POSIX-sh profile half so
    non-interactive shells see them too.
- `jb-setup-system` console entry point.

### Changed

- Adopted the org-wide `standard.mk`: the `Makefile` is now configuration only
    (feature flags, command variables, `include standard.mk`), and `make lint`
    runs the drift, help and ghost gates. `make help` is generated from `##`
    comments; `check-version` is now `version-check`; `make gates`,
    `make docs-check`, `make coverage-gate` and `make ship` are new.
- `mdformat` and its plugins moved from unpinned pre-commit
    `additional_dependencies` into `pyproject.toml`'s dev group, pinned by
    `uv.lock`; the hook dispatches to `make -s lint-mdformat` so it cannot format
    differently from `make format`. Added `mdformat-frontmatter`, without which
    mdformat rewrote `docs/index.md`'s YAML frontmatter into horizontal rules.
- CI's lint job runs `make lint` — the same gate, not a second implementation
    of it.
- `jb.toml` declares this repo's own system packages under `[dev.*]`, so
    `make install-deps` works here.

### Fixed

- The bootstrap now works on curl < 7.71 (RHEL/Oracle/Rocky/Alma 8 ship 7.61) —
    a large enterprise-LTS audience where `curl --retry-all-errors` aborted every
    fetch with "option --retry-all-errors: is unknown", so `jbx`/`install-deps`
    could not run at all. `just-runit` and `setup-system` now probe curl once and
    add `--retry-all-errors` only where it is supported, keeping `--retry` /
    `--retry-connrefused` (which already ride out throttling) everywhere else.
    Regression test shims a 7.61-style curl and asserts the fetch degrades
    instead of aborting.
- `add-line` no longer prints "Not enough arguments" and its help text on the
    normal two-argument call — the else branch fired whenever both `ENTRY` and
    `FILEPATH` were given.
- Version drift: `jb.toml` and `just-runit`'s `_VERSION` (what `jb version`
    prints) sat at 0.1.4 through two releases because neither was in
    `[[tool.bumpversion.files]]`. Both are listed now, and `make version-check`
    gates all four version strings.
- `make lint` could never pass: `trim-trailing-whitespace` and `shfmt` rewrote
    `match.sh`'s bare `[[` line in a loop, each undoing the other.
- `just-runit`: quoted the inner expansion in `${url#${_JBS_BASE}/}`
    (shellcheck SC2295), which otherwise treats the prefix as a glob pattern.

## [0.2.0] — 2026-06-20

### Added

- PyPI packaging: scripts are now installable via `pip install just-bashit` or
    `uv tool install just-bashit`, exposing `jb`, `jbx`, and `jb-inspect` as
    console entry points.
- `CHANGELOG.md` tracking releases in keep-a-changelog format.
- Standardized release process: `make setup`, `make bump-version`,
    `make release-branch`, `make tag-release` Makefile targets.
- Tag-triggered `release.yml` with CI gate, PyPI publish, and GitHub release
    with CHANGELOG notes.

## [0.1.9] — 2026-05-25

### Fixed

- `_JBS_BASE` URLs now always route through `_acquire_jbs` so sibling scripts
    co-land atomically — previously a direct URL bypass could leave the cache in
    a partially-populated state.

### Docs

- Added `llms.txt` for AI/search discoverability.

______________________________________________________________________

## [0.1.8] — 2026-05-25

### Fixed

- Added `pkg` and `toml` to `_JBS_LIBS` so the `install-deps` cache is always
    populated with its own transitive dependencies.

______________________________________________________________________

## [0.1.7] — 2026-05-24

### Added

- Windows/MSYS2 UCRT64 test job in CI.
- `make coverage` target wired to `kcov/kcov` container.

### Fixed

- Cross-platform compatibility: macOS (bash 3.2, BSD date), Alpine (BusyBox),
    Windows (MSYS2 POSIX ERE, `\n` in regex).
- `BASH_XTRACEFD` no longer clobbers kcov coverage collection.
- `bats` submodule used as fallback when system bats is not on `PATH`.

______________________________________________________________________

## [0.1.6] — 2026-05-24

### Added

- `toml.sh` and `pkg.sh` extracted as first-class library modules.
- `inspect` tool: shows resolved tool sources, cache state, and dependency
    graph without executing anything.
- `install-deps` overhauled: better defaults, escape-hatch command override,
    32+ new bats tests raising coverage above 40 %.

### Changed

- CI matrix extended to Debian, Arch, Fedora, Alpine.
- Test suite expanded to 24+ additional tests across all modules.

______________________________________________________________________

## [0.1.5] — 2026-05-23

### Added

- `jb cache` and `jb version` subcommands.
- `jb install` — pre-fetch tools from `jb.toml` into the local cache.
- `jb.toml` auto-discovery (falls back to `jb-deps.toml` for compatibility).

### Fixed

- `mapfile` replaced with `while-read` loop for bash 3.2 compatibility (macOS).
- Stale `_jbs_` helper names renamed to `_jb_`.
- Stale `jr` symlink removed.

______________________________________________________________________

## [0.1.4] — Initial release
