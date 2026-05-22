# path

Source: `src/path.sh`

Resolve the directory containing the calling script, regardless of how it was
invoked (executed or sourced, symlinked or direct).

---

## get-scriptpath

Print the absolute, symlink-resolved path to the directory containing the
calling script.

```bash
. just-bashit/src/path.sh

# In your own script:
SCRIPTDIR=$(get-scriptpath)
. "${SCRIPTDIR}/helpers.sh"
```

### Usage

```
Usage: get-scriptpath [-h]

  Print path to calling script location.

Options:
  -h     Show this message and exit.
```

!!! note
    Copy this function verbatim into your own script rather than sourcing it
    from an external library — that way `BASH_SOURCE[0]` resolves to your
    script's path, not the library's.

---

## set-scriptpath

Set the `SCRIPTPATH` environment variable to the calling script's directory.
Must be called via `eval` so the export propagates to the calling environment.

```bash
. just-bashit/src/path.sh

eval $(set-scriptpath)
echo "${SCRIPTPATH}"  # /absolute/path/to/your/script/dir
```

### Usage

```
Usage: eval $(set-scriptpath) | set-scriptpath [-h]

  Set SCRIPTPATH to path to calling script location.

Options:
  -h     Show this message and exit.
```

!!! warning
    You **must** use `eval $(set-scriptpath)` — calling it without `eval`
    prints the export statement but does not apply it to the current shell.
