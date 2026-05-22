# format

Source: `src/format.sh`

String trimming and colorized output.

---

## trim-from

Trim a string at a marker character, from either direction, with optional
greedy and keep-marker modes.

```bash
. just-bashit/src/format.sh

trim-from 'report.2026.tar.gz'    # report.2026.tar
trim-from -r 'report.2026.tar.gz' # 2026.tar.gz
trim-from -g 'report.2026.tar.gz' # report
```

### Usage

```
Usage: trim-from [-hrfe] [-m MARKER] STRING

  Trim STRING from MARKER (first occurrence, inclusive) to end.

Options:
  -h         Show this message and exit.
  -m MARKER  Character(s) to trim from. Default is '.'.
  -r         Reverse trim. Trim from MARKER to beginning.
  -g         Greedy. Trim from last occurrence of marker.
  -k         Keep MARKER instead of including in trim.
```

### Examples

```bash
trim-from 12.45            # 12
trim-from -r 12.45         # 45
trim-from 12.4.45          # 12.4    (first occurrence)
trim-from -g 12.4.45       # 12      (last occurrence)
trim-from -kg 12.4.45      # 12.     (keep the marker)
trim-from -m MA "HEYMA!"   # HEY
trim-from -rm MA "HEYMA!"  # !
```

---

## color-echo

Print colorized text to stdout using ANSI escape sequences.

```bash
. just-bashit/src/format.sh

color-echo -bc green "Build succeeded"
color-echo -bc red "Build failed"
color-echo -c cyan "Processing..."
```

### Usage

```
Usage: color-echo [OPTIONS] STRING

  Colorize text (default white) and "echo" (printf + trailing newline).

Options:
  -h        Show this message and exit.
  -c COLOR  One of [black|red|green|yellow|blue|magenta|cyan|white].
  -b        Bright or bold version of the requested color.
```

### Colors

| Flag | Color |
|---|---|
| `-c black` | Black |
| `-c red` | Red |
| `-c green` | Green |
| `-c yellow` | Yellow |
| `-c blue` | Blue |
| `-c magenta` | Magenta |
| `-c cyan` | Cyan |
| `-c white` | White (default) |

Add `-b` to any color for the bright/bold variant.
