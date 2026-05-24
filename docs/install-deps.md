# install-deps

`install-deps` installs system packages from a declarative TOML file.
It detects the running OS and package manager automatically, installs all
dependency groups by default, and runs ephemerally via
[`jbx`](just-runit.md) — no local installation required.

```bash
jbx install-deps                  # install all groups (default)
jbx install-deps -g runtime       # runtime packages only
jbx install-deps -n               # dry run — print commands, don't run
```

See [`inspect`](inspect.md) to query what versions are currently installed.

---

## File auto-discovery

When no file argument is given, `install-deps` searches the current working
directory for a deps file in this order:

| Priority | Source | When to use |
|---|---|---|
| 1 | explicit path arg | `jbx install-deps myfile.toml` |
| 2 | `jb-deps.toml` | standalone deps-only file |
| 3 | `jb.toml` | combined tool + deps manifest (recommended) |
| 4 | stdin | piped input, remote URLs |

**Recommended:** put deps directly in `jb.toml` alongside your tool
declarations — one file covers everything `jb` needs.

```toml
# jb.toml
[project]
name    = "my_project"
version = "0.1.0"

[tools.install-deps]
source = "just-bashit:install-deps"
groups = ["runtime", "dev"]       # opt-out of docs group

[tools.inspect]
source = "just-bashit:inspect"
groups = ["runtime", "dev"]

[runtime.apt]
packages = ["libzmq3-dev"]

[runtime.pacman]
packages = ["zeromq"]

[dev.apt]
packages = ["build-essential", "cmake"]

[dev.pacman]
packages = ["base-devel", "cmake"]

[docs.apt]
packages = ["doxygen", "graphviz"]

[docs.pacman]
packages = ["doxygen", "graphviz"]
```

Use a standalone `jb-deps.toml` only when the project doesn't have a
`jb.toml` or you need to keep deps separate.

---

## The deps.toml format

Dependencies are declared using dotted TOML section headers of the form
`[GROUP.PACKAGE_MANAGER]`. Each section has either a `packages` array or
a `cmd` escape hatch.

```toml
[runtime.apt]
packages = [
    "libzmq3-dev",
    "libfftw3-dev",
]

[runtime.pacman]
packages = ["zeromq", "fftw"]

[dev.apt]
packages = [
    "build-essential",
    "cmake",
    "python3-dev",
]

[dev.pacman]
packages = ["base-devel", "cmake", "python"]
```

**Groups** (`runtime`, `dev`, or any name you choose) let you install only
what a given context needs. You can have as many groups as your project
requires — `test`, `ci`, `docs`, etc.

**Supported package managers:**

| Section key | Package manager | Platform |
|---|---|---|
| `apt` | apt-get | Debian, Ubuntu |
| `pacman` | pacman | Arch, CachyOS, Manjaro |
| `brew` | Homebrew | macOS |
| `dnf` | dnf | Fedora, RHEL, Rocky, Alma |
| `zypper` | zypper | openSUSE |
| `apk` | apk | Alpine |
| `msys2` | pacman (UCRT64) | Windows / MSYS2 |

Both multiline and inline array syntax are supported:

```toml
# multiline
[runtime.apt]
packages = [
    "cmake",
    "libzmq3-dev",
]

# inline
[runtime.apt]
packages = ["cmake", "libzmq3-dev"]
```

---

## Version pinning

Package strings are passed verbatim to the package manager. Use the PM's
native version syntax to pin when needed:

```toml
[runtime.apt]
packages = ["libzmq3-dev=4.3.4-1"]   # apt: pkg=version

[runtime.dnf]
packages = ["zeromq-devel-4.3.4"]    # dnf: pkg-version
```

!!! note "pacman has no version-pin syntax"
    `pacman -S pkg` always installs the current repo version.
    Use `cmd` (below) to install directly from the package cache.

---

## Custom commands (`cmd`)

When `packages` isn't expressive enough, replace the entire install command
for a section with `cmd`. The array is executed verbatim; `packages` is
ignored for that group/section:

```toml
# pin via package cache on Arch
[runtime.pacman]
cmd = ["sudo", "pacman", "-U",
       "/var/cache/pacman/pkg/zeromq-4.3.5-3-x86_64.pkg.tar.zst"]

# post-install hook on Debian
[runtime.apt]
cmd = ["bash", "-c", "apt-get install -y libzmq3-dev && ldconfig"]

# install from a private registry
[internal.brew]
cmd = ["brew", "install", "--HEAD", "my-org/tap/mylib"]
```

`cmd` and `packages` can coexist across different sections of the same
group — e.g. `[runtime.pacman]` uses `cmd` while `[runtime.apt]` uses
`packages`.

!!! tip
    `jbx inspect` notes `cmd` sections in `jb.versions` but cannot query
    their installed versions. Use the output to confirm the command ran.

---

## Default groups

By default `install-deps` installs **all groups** defined in the deps file.
This matches the `uv sync` convention — zero config, everything included.

To restrict which groups are installed when no `-g` flag is given, declare
`groups` under `[tools.install-deps]` in `jb.toml`:

```toml
[tools.install-deps]
source = "just-bashit:install-deps"
groups = ["runtime", "dev"]   # docs and test groups excluded by default
```

The `-g` flag always overrides this, regardless of the toml setting.

---

## Installing dependencies

### All groups (default)

```bash
jbx install-deps
```

Installs every group in the file (or the groups listed in
`[tools.install-deps].groups` if set).

### Specific groups

```bash
jbx install-deps -g runtime
jbx install-deps -g dev
jbx install-deps -g runtime,dev,docs
```

### From stdin

```bash
curl -fsSL https://example.com/jb.toml | jbx install-deps
```

---

## Options

| Flag | Long form | Description |
|---|---|---|
| `-h` | `--help` | Show help and exit |
| `-n` | `--dry-run` | Print commands without executing |
| `-v` | `--verbose` | Print section, groups, and packages before acting |
| `-s SECTION` | `--section SECTION` | Override auto-detected package manager |
| `-g GROUP` | `--groups GROUP` | Comma-separated groups to install (overrides all defaults) |
| | `--template [PATH]` | Write scaffold deps.toml to PATH, or stdout if omitted |

---

## Examples

### Dry run — see what would be installed

```bash
jbx install-deps --dry-run
# sudo pacman -Sy --needed --noconfirm zeromq fftw
# sudo pacman -Sy --needed --noconfirm base-devel cmake python

jbx install-deps --dry-run -g runtime
# sudo pacman -Sy --needed --noconfirm zeromq fftw
```

### Verbose output

```bash
jbx install-deps --dry-run --verbose
# section:  pacman
# groups:   runtime,dev
# packages: zeromq fftw
# sudo pacman -Sy --needed --noconfirm zeromq fftw
# packages: base-devel cmake python
# sudo pacman -Sy --needed --noconfirm base-devel cmake python
```

### Override the detected package manager

Useful in containers or CI where auto-detection picks the wrong manager:

```bash
jbx install-deps --section apt
jbx install-deps -s dnf -g runtime
```

### Scaffold a new deps.toml

```bash
jbx install-deps --template            # print to stdout
jbx install-deps --template deps.toml  # write to file
```

### Pin to a specific script commit for reproducible CI

```bash
jbx gh:just-buildit/just-bashit/src/install-deps.sh@abc1234
```

---

## Scaffold a new deps.toml

Generate a fully-populated template with all groups and package manager
sections pre-filled with placeholder comments:

```bash
jbx install-deps --template            # stdout
jbx install-deps --template deps.toml  # write to file
```

The generated file includes usage instructions and example values for every
supported section. Delete the sections you don't need, fill in the rest.

---

## Windows / MSYS2

`msys2` sections are never executed directly — the script always prints
the equivalent `pacman` command for you to run manually in a UCRT64 shell:

```toml
[runtime.msys2]
packages = [
    "mingw-w64-ucrt-x86_64-zeromq",
    "mingw-w64-ucrt-x86_64-fftw",
]
```

```bash
install-deps.sh deps.toml
# Windows/MSYS2: open a UCRT64 shell and run:
#   pacman -S mingw-w64-ucrt-x86_64-zeromq mingw-w64-ucrt-x86_64-fftw
```

!!! warning "Use the UCRT64 shell, not MSYS"
    The MSYS POSIX compiler and the UCRT64 native compiler have incompatible
    headers. Always launch from the **UCRT64** shortcut so `/ucrt64/bin`
    is first on `PATH`.

---

## Platform detection

The package manager is inferred from `/etc/os-release` on Linux and
`uname -s` elsewhere. The mapping:

| `ID` / `ID_LIKE` contains | Section |
|---|---|
| `debian`, `ubuntu` | `apt` |
| `arch`, `cachyos`, `manjaro` | `pacman` |
| `fedora`, `rhel`, `centos`, `rocky`, `alma` | `dnf` |
| `suse` | `zypper` |
| `alpine` | `apk` |
| Darwin (`uname`) | `brew` |
| MINGW / MSYS / CYGWIN (`uname`) | `msys2` |

If detection fails, use `--section` to specify the package manager explicitly.

---

## Shell compatibility

`install-deps.sh` requires **bash 3.2 or later** — compatible with the
system bash shipped on macOS (bash 3.2.57, GPL-2). No bash 4+ features are
used: no `mapfile`/`readarray`, no associative arrays (`declare -A`), no
`[[ =~ ]]` capture groups.

| Shell | Minimum version | Notes |
|---|---|---|
| bash | 3.2+ | macOS default `/bin/bash` works |
| zsh | not supported | run via `bash install-deps.sh` explicitly |
| dash / sh | not supported | arrays and process substitution required |

If your environment ships an older bash or a non-bash shell as `/bin/sh`,
invoke the script directly:

```bash
bash install-deps.sh -g runtime,dev
```

or via `jbx`, which always runs scripts under `bash`:

```bash
jbx install-deps
```
