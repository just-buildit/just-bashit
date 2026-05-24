# pkg

Source: `src/pkg.sh`

Package manager detection and installed-version querying.

---

## get-pkg-mgr

Print the name of the active package manager for the running OS.
Returns non-zero and prints to stderr if the OS is unrecognised.

```bash
. just-bashit/src/pkg.sh

pm=$(get-pkg-mgr)          # e.g. "pacman" on Arch, "apt" on Debian
echo "Using ${pm}"
```

### Usage

```
Usage: get-pkg-mgr

  Print the name of the active package manager for the running OS.

Options:
  -h  Show this message and exit.

Output:
  One of: apt, pacman, brew, dnf, zypper, apk, msys2.
```

### OS mapping

| OS / distro family | Output |
|---|---|
| macOS | `brew` |
| Debian, Ubuntu | `apt` |
| Arch, CachyOS, Manjaro | `pacman` |
| Fedora, RHEL, CentOS, Rocky, AlmaLinux | `dnf` |
| openSUSE | `zypper` |
| Alpine | `apk` |
| MSYS2 / Cygwin / MinGW | `msys2` |

---

## get-pkg-version

Print the installed version of a package using the specified package manager.
Prints nothing (not an error) if the package is not installed.

```bash
. just-bashit/src/pkg.sh

get-pkg-version apt curl           # e.g. "8.5.0-2"
get-pkg-version pacman bash        # e.g. "5.2.37-1"
get-pkg-version pacman nosuchpkg   # prints nothing, exits 0
```

### Usage

```
Usage: get-pkg-version PM PKG

  Print the installed version of PKG using package manager PM.
  Prints nothing (not an error) if the package is not installed.

Options:
  -h  Show this message and exit.

Arguments:
  PM   Package manager name: apt, pacman, brew, dnf, zypper, apk, msys2.
  PKG  Package name as known to the package manager.
```

### Examples

```bash
# Check if curl is installed and get its version
ver=$(get-pkg-version "$(get-pkg-mgr)" curl)
if [[ -n "${ver}" ]]; then
    echo "curl ${ver} is installed"
else
    echo "curl is not installed"
fi
```
