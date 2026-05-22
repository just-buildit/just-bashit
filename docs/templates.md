# Templates

Source: `src/function-template.sh`, `src/script-template`

Copy-paste starting points for new bash functions and scripts. Take only what
you need.

---

## full-on-template

A complete function template demonstrating every common pattern:
getopts-based option parsing, a heredoc help string, variable initialization
before and after `getopts`, and a nested helper function.

```bash
. just-bashit/src/function-template.sh

full-on-template -h  # show usage
full-on-template -p myvalue arg1 arg2
```

Use this when your function needs multiple options, some with arguments.

---

## minimalist-template

A stripped-down function template for simple functions that don't need the
full getopts machinery.

```bash
. just-bashit/src/function-template.sh

minimalist-template -h
minimalist-template arg1
```

Use this as a starting point and add complexity only as needed.

---

## script-template

An executable script template (not a library) demonstrating:

- Bash strict mode: `set -euo pipefail`
- `IFS` configuration
- `EXIT` trap for cleanup
- `getopts`-based option parsing

```bash
# Copy and rename
cp just-bashit/src/script-template my-script
chmod +x my-script
./my-script -h
```

The template is intentionally self-contained — it does not source any
just-bashit libraries, so it works as a standalone starting point.
