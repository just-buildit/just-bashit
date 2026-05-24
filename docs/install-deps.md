# install-deps

`install-deps` installs system packages from a declarative TOML file.
It detects the running OS and package manager automatically, supports
multiple dependency groups (e.g. `runtime` vs `dev`), and runs ephemerally
via [`jbx`](just-runit.md) — no local installation required.

```bash
jbx install-deps          # auto-discovers jb.toml or jb-deps.toml in CWD
jbx install-deps -g dev   # dev/build tools only
```

---

## File auto-discovery

When no file argument is given, `install-deps` searches the current working
directory for a deps file in this order:

| Priority | Filename | When to use |
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
groups = ["runtime", "dev"]

[runtime.apt]
packages = ["libzmq3-dev"]

[runtime.pacman]
packages = ["zeromq"]

[dev.apt]
packages = ["build-essential", "cmake"]

[dev.pacman]
packages = ["base-devel", "cmake"]
```

Use a standalone `jb-deps.toml` only when the project doesn't have a
`jb.toml` or you need to keep deps separate.

---

## The deps.toml format

Dependencies are declared in a `deps.toml` file using dotted TOML section
headers of the form `[GROUP.PACKAGE_MANAGER]`. Each section contains a
single `packages` array.

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

## Scaffold a new deps.toml

Generate a fully-populated template with all groups and package manager
sections pre-filled with placeholder comments:

```bash
# Print to stdout
install-deps.sh --template

# Write directly to a file
install-deps.sh --template deps.toml
```

Or ephemerally:

```bash
jbx gh:just-buildit/just-bashit/src/install-deps.sh --template deps.toml
```

The generated file includes usage instructions and example values for every
supported section. Delete the sections you don't need, fill in the rest.

---

## Installing dependencies

### Runtime only (default)

```bash
jbx install-deps
```

Auto-detects the OS, discovers the deps file, and installs the
`[runtime.<detected>]` section.

### Dev / build tools

```bash
jbx install-deps -g dev
```

### Runtime + dev together

```bash
jbx install-deps -g runtime,dev
```

### From stdin

```bash
curl -fsSL https://example.com/jb.toml | jbx install-deps -g runtime,dev
```

---

## Options

| Flag | Long form | Description |
|---|---|---|
| `-h` | `--help` | Show help and exit |
| `-n` | `--dry-run` | Print the install command without executing |
| `-v` | `--verbose` | Print detected section, groups, and packages before acting |
| `-s SECTION` | `--section SECTION` | Override auto-detected package manager |
| `-g GROUP` | `--groups GROUP` | Comma-separated groups to install (default: `runtime`) |
| | `--template [PATH]` | Write scaffold deps.toml to PATH, or stdout if omitted |

---

## Examples

### Dry run — see what would be installed

```bash
jbx install-deps --dry-run
# sudo pacman -Sy --needed --noconfirm zeromq fftw

jbx install-deps --dry-run -g runtime,dev
# sudo pacman -Sy --needed --noconfirm zeromq fftw base-devel cmake python
```

### Verbose output

```bash
jbx install-deps --dry-run --verbose
# section:  pacman
# groups:   runtime
# packages: zeromq fftw
# sudo pacman -Sy --needed --noconfirm zeromq fftw
```

### Override the detected package manager

Useful in containers, CI, or cross-platform scripts where auto-detection
would pick the wrong manager:

```bash
jbx install-deps --section apt
jbx install-deps -s dnf -g runtime,dev
```

### Multiple groups in CI

```bash
jbx install-deps -g runtime,dev,test
```

### Pin to a specific commit for reproducible CI

```bash
jbx gh:just-buildit/just-bashit/src/install-deps.sh@abc1234
```

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
jbx install-deps -g runtime,dev
```
