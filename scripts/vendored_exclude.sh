#!/bin/sh
# Write .pre-commit-config.yaml's shfmt `exclude:` from VENDORED_FILES.
#
# shfmt reformats every shell file it is handed; `standard-check` requires a
# vendored file to be byte-identical to canonical. Formatting one guarantees
# the drift gate fails, and passing the drift gate guarantees the formatter
# reports a diff -- the two rules are JOINTLY IMPOSSIBLE unless the vendored
# copies are kept away from the formatter. They are not this repo's code to
# format; they are changed at canonical and re-vendored.
#
# The list therefore existed twice: once as VENDORED_FILES in the Makefile,
# and once as a hand-written regex in the YAML. It was already wrong. Two
# files were added to VENDORED_FILES and the regex still named only the
# first, so shfmt was free to rewrite the other two -- and they survived
# purely because they had been formatted in this repo's style before being
# published to canonical. A coincidence is not an exclusion.
#
# So the Makefile declares, and this GENERATES the regex. Like every other
# lint target here it WRITES: pre-commit fails on "files were modified by this
# hook", which makes the fixer and the gate the same command and stops them
# disagreeing about what correct looks like.
#
# Usage:  vendored_exclude.sh <config> [vendored-file ...]
set -eu

CONFIG=${1:?usage: vendored_exclude.sh <config> [vendored-file ...]}
shift

# Only shell files matter: shfmt is handed nothing else, and naming a .mk or a
# .ps1 here would be an exclusion that never fires -- which reads as a rule and
# behaves as a comment.
alt=""
for f in "$@"; do
	case "$f" in
	*.sh) ;;
	*) continue ;;
	esac
	# Escape the regex metacharacter that actually occurs in these paths. A
	# bare dot matches any character, so `release-watch.sh` would also exclude
	# `release-watchXsh` -- harmless today, wrong on principle, and free to fix.
	esc=$(printf '%s' "$f" | sed 's/\./\\./g')
	alt=${alt:+$alt|}$esc
done

if [ -z "$alt" ]; then
	echo "vendored-exclude: no vendored shell files -- nothing to exclude" >&2
	exit 1
fi

want="        exclude: ^($alt)\$"

# Exactly one match, required. Replacing "the exclude line" in a file that has
# grown a second one would silently rewrite the wrong hook's rule, and finding
# none would silently do nothing at all -- the two failure modes this check
# exists to prevent.
n=$(grep -c '^        exclude: ' "$CONFIG" || true)
if [ "$n" != "1" ]; then
	echo "vendored-exclude: expected exactly 1 exclude line in $CONFIG, found $n" >&2
	echo "  This rewrites the shfmt hook's exclude and nothing else. If another" >&2
	echo "  hook now needs one, teach this script which is which first." >&2
	exit 1
fi

have=$(grep '^        exclude: ' "$CONFIG")
if [ "$have" = "$want" ]; then
	echo "vendored-exclude: shfmt excludes exactly the $# vendored file(s)"
	exit 0
fi

tmp=$(mktemp)
# awk over sed: the replacement contains | and \ and / and $, and every one of
# them means something to sed's s/// depending on the delimiter chosen.
#
# Through ENVIRON, not -v: `awk -v x='a\.b'` processes escape sequences in the
# assignment, so the backslashes that make this a regex were eaten before awk
# ever ran and the file got `release-watch.sh` where it needed
# `release-watch\.sh`. awk warns about it ("escape sequence `\.' treated as
# plain `.'"), and the printed message still looked right because that came
# from the shell variable. ENVIRON does no such processing.
WANT="$want" awk '
    /^        exclude: / { print ENVIRON["WANT"]; next }
    { print }
' "$CONFIG" >"$tmp"
mv "$tmp" "$CONFIG"

echo "vendored-exclude: rewrote the shfmt exclude from VENDORED_FILES"
echo "  was: $have"
echo "  now: $want"
