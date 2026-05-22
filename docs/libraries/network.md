# network

Source: `src/network.sh`

Network connectivity testing. Depends on `format.sh` and `environment.sh`.

---

## test-internet-access

Test internet connectivity by probing URLs with `curl`, `wget`, and/or `ping`
(whichever are available). Returns 0 on first success, 1 if all fail, 124 on
timeout.

```bash
. just-bashit/src/network.sh

# Silent check — returns 0/1
test-internet-access && echo "online" || echo "offline"

# Verbose with 10s timeout
test-internet-access -vt 10

# Test specific hosts
test-internet-access bing.com 1.1.1.1
```

### Usage

```
Usage: test-internet-access [-hv] [-t TIMEOUT] [URL] ...

  Test internet connection and return PASS(0)/FAIL(1).

Options:
  -h          Show this message and exit.
  -v          Verbose mode. Prints status messages.
  -t TIMEOUT  Total test timeout in seconds (default 20). Disable with 'false'.

Arguments:
  URL         URLs (e.g. google.com) and/or IPs (e.g. 1.1.1.1) to test.
```

### Default Targets

When no URLs are given, the function tests:
`https://example.com`, `https://pypi.org`, `https://google.com`

### Exit Codes

| Code | Meaning |
|---|---|
| `0` | Connection established |
| `1` | All probes failed |
| `124` | Timeout expired before any success |

### Examples

```bash
# Silently test multiple sites with 20s timeout (default)
test-internet-access

# Verbose, 10s timeout
test-internet-access -vt 10

# Fast check — 1s timeout, two specific targets
test-internet-access -t 1 bing.com 1.1.1.1

# No timeout (run until all probes complete)
test-internet-access -t false
```
