# environment

Source: `src/environment.sh`

Idempotent management of `~/.bashrc` entries and command existence checks.

---

## set-bashrc

Write a line to `~/.bashrc` only if it is not already present.

```bash
. just-bashit/src/environment.sh

# Write a verbatim line
set-bashrc 'alias ll="ls -la"'

# Write an export KEY=VALUE pair
set-bashrc MY_TOOL /usr/local/bin/my-tool
# writes: export MY_TOOL=/usr/local/bin/my-tool
```

### Usage

```
Usage: set-bashrc [OPTIONS] KEY_OR_ENTRY [VALUE] ...

  Write a line to ~/.bashrc ONLY if not already present.

Options:
  -h        Show this message and exit.

Arguments:
  KEY_OR_ENTRY  Line to write verbatim if given alone, otherwise interpreted
                as a KEY given VALUE is provided to complete the pair. In the
                latter case the line written is "export KEY=VALUE".
  VALUE         The value associated with the provided KEY.
```

---

## unset-bashrc

Remove a line from `~/.bashrc` if present. No-op if not found.

```bash
. just-bashit/src/environment.sh

# Remove a verbatim line
unset-bashrc 'alias ll="ls -la"'

# Remove an export KEY=VALUE pair
unset-bashrc MY_TOOL /usr/local/bin/my-tool
# removes: export MY_TOOL=/usr/local/bin/my-tool
```

### Usage

```
Usage: unset-bashrc [OPTIONS] KEY_OR_ENTRY [VALUE] ...

  Remove requested line from ~/.bashrc if present.

Options:
  -h        Show this message and exit.

Arguments:
  KEY_OR_ENTRY  Line to remove verbatim if given alone, otherwise interpreted
                as a KEY, given VALUE is provided to complete the pair. In the
                latter case the line searched for is "export KEY=VALUE".
  VALUE         The value associated with the provided KEY.
```

---

## check-command-exists

Return 0 if a command is available in `PATH`, 1 otherwise.

```bash
. just-bashit/src/environment.sh

check-command-exists curl && echo "curl is available"
check-command-exists nonexistent || echo "not found"
```

### Usage

```
Usage: check-command-exists [-h] COMMAND

  Does just that. Exits with 0 if true, 1 if false.

Options:
  -h     Show this message and exit.
```
