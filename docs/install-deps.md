# install-deps

`install-deps.sh` installs system packages from a declarative TOML file.
It detects the running OS and package manager automatically, supports
multiple dependency groups (e.g. `runtime` vs `dev`), and is designed to
be invoked ephemerally via [`just-runit`](just-runit.md) — no local
installation required.

```bash
jx gh:just-buildit/just-bashit/src/install-deps.sh < deps.toml
```

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
jx gh:just-buildit/just-bashit/src/install-deps.sh --template deps.toml
```

The generated file includes usage instructions and example values for every
supported section. Delete the sections you don't need, fill in the rest.

---

## Installing dependencies

### Runtime only (default)

```bash
install-deps.sh deps.toml
```

Auto-detects the OS and installs the `[runtime.<detected>]` section.

### Dev / build tools

```bash
install-deps.sh -g dev deps.toml
```

### Runtime + dev together

```bash
install-deps.sh -g runtime,dev deps.toml
```

### From stdin

```bash
cat deps.toml | install-deps.sh
install-deps.sh < deps.toml

# From a remote URL via curl
curl -fsSL https://example.com/deps.toml | install-deps.sh -g runtime,dev
```

### Via just-runit (no local install)

```bash
jx gh:just-buildit/just-bashit/src/install-deps.sh < deps.toml
jx gh:just-buildit/just-bashit/src/install-deps.sh -g runtime,dev < deps.toml
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
install-deps.sh --dry-run deps.toml
# sudo pacman -Sy --needed --noconfirm zeromq fftw

install-deps.sh --dry-run -g runtime,dev deps.toml
# sudo pacman -Sy --needed --noconfirm zeromq fftw base-devel cmake python
```

### Verbose output

```bash
install-deps.sh --dry-run --verbose deps.toml
# section:  pacman
# groups:   runtime
# packages: zeromq fftw
# sudo pacman -Sy --needed --noconfirm zeromq fftw
```

### Override the detected package manager

Useful in containers, CI, or cross-platform scripts where auto-detection
would pick the wrong manager:

```bash
install-deps.sh --section apt deps.toml
install-deps.sh -s dnf -g runtime,dev deps.toml
```

### Multiple groups in CI

```bash
# Install everything needed to build and test
install-deps.sh -g runtime,dev,test deps.toml
```

### Pin to a specific commit for reproducible CI

```bash
jx gh:just-buildit/just-bashit/src/install-deps.sh@abc1234 < deps.toml
```

### Thin project shim

Projects that want a one-step `./install-deps.sh` without requiring
`jx` on the caller's `PATH` can include a shim:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JBS="gh:just-buildit/just-bashit/src/install-deps.sh"

if command -v jx >/dev/null 2>&1; then
    jx "${JBS}" "$@" <"${SCRIPT_DIR}/deps.toml"
elif command -v just-runit >/dev/null 2>&1; then
    just-runit "${JBS}" "$@" <"${SCRIPT_DIR}/deps.toml"
elif [ -f "${SCRIPT_DIR}/../just-bashit/src/install-deps.sh" ]; then
    bash "${SCRIPT_DIR}/../just-bashit/src/install-deps.sh" "$@" \
        "${SCRIPT_DIR}/deps.toml"
else
    echo "error: just-runit (jx) not found." >&2
    exit 1
fi
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
