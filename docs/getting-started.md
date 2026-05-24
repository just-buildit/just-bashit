# Getting Started

## Installation

Download the latest release from
[GitHub Releases](https://github.com/just-buildit/just-bashit/releases) and
extract it:

```bash
tar xf just-bashit.tar.gz
```

This gives you:

```
just-bashit/
├── README.md
├── src/
│   ├── datetime.sh
│   ├── environment.sh
│   ├── file.sh
│   ├── format.sh
│   ├── function-template.sh
│   ├── logging.sh
│   ├── match.sh
│   ├── network.sh
│   ├── path.sh
│   └── script-template
└── test-results/
```

## Sourcing Libraries

All libraries **must be sourced**, not executed. Each file enforces this at
load time and will exit with an error if you try to run it directly.

```bash
. just-bashit/src/logging.sh   # correct
bash just-bashit/src/logging.sh # error: "This file must be sourced."
```

Some libraries depend on others (`logging.sh` sources `format.sh`,
`match.sh`, and `datetime.sh`). The safest approach is to keep the entire
extracted package together and source only the files you need — the sourcing
chain resolves automatically from relative paths.

## Getting Help

Every function accepts `-h`:

```bash
. just-bashit/src/datetime.sh
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
