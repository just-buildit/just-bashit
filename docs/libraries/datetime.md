# datetime

Source: `src/datetime.sh`

## iso-8601-basic

Generate a path- and filename-friendly ISO 8601 UTC timestamp.

```bash
. just-bashit/src/datetime.sh
iso-8601-basic
# 20260522T143200Z
```

### Usage

```
Usage: iso-8601-basic [-d DATE] [-m|u|n]

  Basic-Format ISO 8601 Timestamp.

Options:
  -h       Show this message and exit.
  -d DATE  UTC date and time to use instead of the default 'now'.
  -m       Show milliseconds (default is seconds).
  -u       Show microseconds (default is seconds).
  -n       Show nanoseconds (default is seconds).
```

### Output Format

```
YYYYMMDDThhmmss[.fff[fff[fff]]]Z
```

Only path-safe characters are used — no colons, spaces, or punctuation other
than `.` and `Z`.

### Examples

```bash
# Current time, second resolution
iso-8601-basic
# 20260522T143200Z

# Millisecond resolution
iso-8601-basic -m
# 20260522T143200.123Z

# Microsecond resolution
iso-8601-basic -u
# 20260522T143200.123456Z

# Nanosecond resolution
iso-8601-basic -n
# 20260522T143200.123456789Z

# Specific date/time
iso-8601-basic -d '10:32 AM EDT Jan 5 1982'
# 19820105T143200Z

# Milliseconds for a specific date
iso-8601-basic -m -d 'yesterday'
# 20260521T000000.000Z
```
