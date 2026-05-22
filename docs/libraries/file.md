# file

Source: `src/file.sh`

Idempotent line-level file content management.

---

## add-line

Write a line to a file only if it is not already present. Optionally write a
blank line.

```bash
. just-bashit/src/file.sh

# Append a line (idempotent — safe to call repeatedly)
add-line "export PATH=$PATH:/opt/myapp/bin" /etc/environment

# Append a blank line
add-line /etc/environment

# Suppress blank lines with -x
add-line -x "" /etc/environment  # no-op
```

### Usage

```
Usage: add-line [OPTIONS] [ENTRY] FILEPATH ...

  Write ENTRY to FILEPATH only if not already present. If one argument is
  given it is taken as FILEPATH and a blank line is written.

Options:
  -h        Show this message and exit.
  -x        Don't write blank lines.

Arguments:
  ENTRY     Line to write verbatim.
  FILEPATH  Path to file for writing.
```

---

## remove-line

Remove a line from a file if present. No-op if not found.

```bash
. just-bashit/src/file.sh

remove-line "export PATH=$PATH:/opt/myapp/bin" /etc/environment

# Remove blank lines
remove-line /etc/environment

# Skip blank-line removal with -x
remove-line -x /etc/environment
```

### Usage

```
Usage: remove-line [OPTIONS] [ENTRY] FILEPATH ...

  Remove ENTRY from FILEPATH if present.

Options:
  -h        Show this message and exit.
  -x        Don't remove blank lines.

Arguments:
  ENTRY     Line to remove verbatim.
  FILEPATH  Path to file for line removal.
```

---

## add-contents

Copy every line from one file into another, skipping duplicates.

```bash
. just-bashit/src/file.sh

# Merge new.conf into existing.conf without duplicating lines
add-contents new.conf existing.conf

# Skip blank lines
add-contents -x new.conf existing.conf
```

### Usage

```
Usage: add-contents [OPTIONS] FROMPATH TOPATH ...

  Write each line of FROMPATH to TOPATH only if not already present in TOPATH.

Options:
  -h        Show this message and exit.
  -x        Don't write blank lines.

Arguments:
  FROMPATH  Path to file for reading lines.
  TOPATH    Path to file for writing lines.
```
