# Getting Started

## Installation

### jbx

Most people want `jbx` (`just-runit`), which runs any script or library
function by name, fetching it on demand. One line installs it into the shell
you run it in:

```bash
. <(curl -sSL https://just-buildit.github.io/get-jb.sh)
```

What that installs, why it is sourced, and how to reinstall are in
[Getting just-runit](just-runit.md#getting-just-runit). From there,
`jbx setup-system` sets up the rest of the machine.

### The libraries

To source the libraries from your own scripts, download `just-bashit.tar.gz`
from [GitHub Releases](https://github.com/just-buildit/just-bashit/releases)
and extract it into a `just-bashit/` directory, which is the path every example
in these docs sources from:

```bash
mkdir -p just-bashit
tar xzf just-bashit.tar.gz -C just-bashit
ls just-bashit/src/just_bashit/   # logging.sh, path.sh, match.sh, ...
```

## Sourcing Libraries

All libraries **must be sourced**, not executed. Each file enforces this at
load time and will exit with an error if you try to run it directly.

```bash
. just-bashit/src/just_bashit/logging.sh   # correct
bash just-bashit/src/just_bashit/logging.sh # error: "This file must be sourced."
```

Some libraries depend on others (`logging.sh` sources `format.sh`,
`match.sh`, and `datetime.sh`). The safest approach is to keep the entire
extracted package together and source only the files you need — the sourcing
chain resolves automatically from relative paths.

## Getting Help

Every function accepts `-h`:

```bash
. just-bashit/src/just_bashit/datetime.sh
iso-8601-basic -h
```

```
Usage: iso-8601-basic [-d DATE] [-m|u|n]

  Basic-Format ISO 8601 Timestamp.

Options:
  -h       Show this message and exit.
  -d DATE  UTC date and time to use instead of the default 'now'.
  -m       Show milliseconds (default is seconds).
  -u       Show microseconds (default is seconds).
  -n       Show nanoseconds (default is seconds).
...
```

## Platform Support

Every release is tested on:

- **Debian** (latest) · **Arch Linux** (latest) · **Fedora** (latest) · **Alpine** (latest)
- **macOS** (latest, with GNU coreutils via Homebrew)
- **Windows** — MSYS2 UCRT64

All libraries target bash 4.0+ on Linux. macOS ships bash 3.2; the libraries
that run on macOS avoid bash-4-only features (e.g. `${var,,}`, `mapfile`).

## Quality Guarantees

Every library in a release:

- Passes `shellcheck` static analysis
- Is formatted with `shfmt`
- Has a corresponding `bats` test suite with kcov coverage
- Is tested on all six supported platforms in CI

Pre-commit hooks enforce the same checks locally when contributing.
