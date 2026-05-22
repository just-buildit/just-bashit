# match

Source: `src/match.sh`

Regex pattern constants and numeric validation.

---

## Pattern Constants

Exported variables for use in `[[ =~ ]]` expressions:

| Variable | Matches |
|---|---|
| `IS_NUMBER` | Unsigned integer or decimal (`5`, `5.`, `.5`, `22.5`) |
| `IS_SIGNED_NUMBER` | Signed integer or decimal (`-5`, `+5.3`) |
| `IS_ONLY_NUMBER` | `IS_NUMBER` anchored to full string |
| `IS_ONLY_SIGNED_NUMBER` | `IS_SIGNED_NUMBER` anchored to full string |

```bash
. just-bashit/src/match.sh

[[ "3.14" =~ $IS_ONLY_NUMBER ]] && echo "numeric"
[[ "-7"   =~ $IS_ONLY_SIGNED_NUMBER ]] && echo "signed numeric"
```

---

## is-number

Return 0 (PASS) if a string is a valid number, 1 (FAIL) otherwise.

```bash
. just-bashit/src/match.sh

is-number 42      # PASS
is-number 3.14    # PASS
is-number .5      # PASS
is-number five    # FAIL
is-number -5      # FAIL (unsigned by default)
is-number -s -5   # PASS (allow signed with -s)
is-number -s +5   # PASS
```

### Usage

```
Usage: is-number [-hs] [STRING]

  PASS (return 0) if STRING is a number otherwise FAIL (return 1).

Options:
  -h      Show this message and exit.
  -s      Allow signed numbers.

Arguments:
  STRING  String to test.
```

### Examples

```bash
is-number five   # FAIL
is-number -5     # FAIL
is-number +5     # FAIL
is-number -s -5  # PASS
is-number -s +5  # PASS
is-number 5      # PASS
is-number 5.     # PASS
is-number .5     # PASS
is-number 22.5   # PASS
```
