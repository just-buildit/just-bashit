# logging

Source: `src/logging.sh`

Structured, colorized logging with timestamps. Depends on `format.sh`,
`match.sh`, and `datetime.sh` — all resolved automatically from relative paths.

---

## log

Log a message to stdout with a timestamp and type label.

```bash
. just-bashit/src/logging.sh

log "Starting deployment"
# [20260522T143200Z::INFO]::Starting deployment

log -t SUCCESS "Deploy complete"
# [20260522T143200Z::SUCCESS]::Deploy complete (green)

log -t ERROR "Connection refused"
# [20260522T143200Z::ERROR]::Connection refused (red)
```

### Usage

```
Usage: log [-hmun] [-t TYPE] [-c COLORS] [-s 'TYPE COLOR'] [MESSAGE]

  Log to stdout with format: {TIMESTAMP}::{TYPE} {MESSAGE}.

Options:
  -h               Show this message and exit.
  -m               Millisecond timestamp resolution.
  -u               Microsecond timestamp resolution.
  -n               Nanosecond timestamp resolution.
  -t TYPE          One of [INFO|WARNING|DEBUG|ERROR|SUCCESS]. Default: INFO.
  -c COLORS        One of [AUTO|ON|OFF]. Default: AUTO (on when stdout is a tty).
  -s 'TYPE COLOR'  Custom type and color. COLOR must be one of the
                   color-echo values. Enclose both words in quotes.
```

### Log Types and Colors

| Type | Color |
|---|---|
| `INFO` | White |
| `WARNING` | Yellow |
| `DEBUG` | Yellow |
| `ERROR` | Red |
| `SUCCESS` | Green |

### Examples

```bash
# Millisecond timestamps
log -m "Checkpoint reached"
# [20260522T143200.123Z::INFO]::Checkpoint reached

# Custom type and color
log -s 'DEPLOY blue' "Pushing image"
# [20260522T143200Z::DEPLOY]::Pushing image (blue)

# Force color off (e.g. when redirecting to a file)
log -c OFF -t WARNING "Disk usage above 90%"
```

---

## log-wait

Sleep for a given duration with input validation.

```bash
. just-bashit/src/logging.sh

log-wait 5      # sleep 5 seconds
log-wait 0.5    # sleep 500ms
log-wait        # sleep 1 second (default)
```

### Usage

```
Usage: log-wait [-h] DURATION

  Sleep for given duration (default 1 second).

Options:
  -h        Show this message and exit.

Arguments:
  DURATION  Duration to sleep in seconds. Default is 1 second.
```

Returns 1 if `DURATION` is not a valid number.
