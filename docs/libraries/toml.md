# toml

Source: `src/toml.sh`

Pure-bash parser for the TOML subset used by just-bashit dependency files:
`[group.pm]` sections with `packages = [...]` and `cmd = [...]` arrays.
All parse functions read from stdin.

---

## toml_strings

Extract each double-quoted string value from a TOML fragment, one per line.
Skips empty quoted strings.

```bash
. just-bashit/src/toml.sh

toml_strings '"curl", "wget"'       # prints: curl\nwget
toml_strings '"a", "", "b"'         # prints: a\nb  (empty string skipped)
```

### Usage

```
Usage: toml_strings TEXT

  Extract each double-quoted string value from TEXT, one per line.

Options:
  -h  Show this message and exit.

Arguments:
  TEXT  Raw TOML fragment containing one or more double-quoted strings.
```

---

## toml_get_array

Print each value in `KEY = [...]` under `[GROUP.SECTION]`, one per line.
Handles both inline and multiline array syntax. Reads TOML from stdin.

```bash
printf '[runtime.apt]\npackages = ["curl", "wget"]\n' \
    | toml_get_array runtime apt packages
# prints: curl\nwget
```

### Usage

```
Usage: toml_get_array GROUP SECTION KEY   (stdin: TOML content)

  Print each value in KEY = [...] under [GROUP.SECTION], one per line.

Options:
  -h  Show this message and exit.

Arguments:
  GROUP    The top-level group name (e.g. "runtime", "dev").
  SECTION  The package manager or sub-section (e.g. "apt", "pacman").
  KEY      The array key to extract (e.g. "packages", "cmd").
```

---

## toml_get_packages

Print `packages = [...]` values from `[GROUP.SECTION]`, one per line.
Shorthand for `toml_get_array GROUP SECTION packages`.

```bash
cat deps.toml | toml_get_packages runtime apt
```

### Usage

```
Usage: toml_get_packages GROUP SECTION   (stdin: TOML content)

Options:
  -h  Show this message and exit.

Arguments:
  GROUP    The top-level group name (e.g. "runtime", "dev").
  SECTION  The package manager name (e.g. "apt", "pacman").
```

---

## toml_get_cmd

Print `cmd = [...]` values from `[GROUP.SECTION]`, one per line.
Shorthand for `toml_get_array GROUP SECTION cmd`.

```bash
cat deps.toml | toml_get_cmd runtime apt
```

### Usage

```
Usage: toml_get_cmd GROUP SECTION   (stdin: TOML content)

Options:
  -h  Show this message and exit.

Arguments:
  GROUP    The top-level group name (e.g. "runtime", "dev").
  SECTION  The package manager name (e.g. "apt", "pacman").
```

---

## toml_get_tool_groups

Print comma-separated group names from `[tools.TOOL].groups = [...]`.
Returns nothing if the key is absent. Reads TOML from stdin.

```bash
cat jb.toml | toml_get_tool_groups install-deps
# prints e.g.: runtime,dev
```

### Usage

```
Usage: toml_get_tool_groups TOOL   (stdin: TOML content)

Options:
  -h  Show this message and exit.

Arguments:
  TOOL  The tool name as it appears in [tools.TOOL] (e.g. "install-deps").
```

---

## toml_discover_groups

Scan for `[group.pm]` headers where `pm` is a known package manager.
Print comma-separated group names in file order, deduplicated.
Pass custom PM names to override the built-in list. Reads TOML from stdin.

```bash
cat deps.toml | toml_discover_groups
# prints e.g.: runtime,dev

cat deps.toml | toml_discover_groups apt pacman
# only recognises apt and pacman sections
```

### Usage

```
Usage: toml_discover_groups [PM ...]   (stdin: TOML content)

Options:
  -h  Show this message and exit.

Arguments:
  PM ...  Optional list of package manager names to recognise.
          Defaults to: apt pacman brew dnf zypper apk msys2.
```

### Supported package managers (default)

`apt`, `pacman`, `brew`, `dnf`, `zypper`, `apk`, `msys2`
