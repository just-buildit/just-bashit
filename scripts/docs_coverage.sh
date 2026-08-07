#!/usr/bin/env bash
# ############################################################################
# docs_coverage.sh — repo gate, not a shipped library.                       #
# ############################################################################
# Two invariants, because make-run shipped in 0.4.0 breaking both and nothing #
# said so: it was documented nowhere, and a page written for it would still   #
# have been invisible without a nav entry.                                   #
#                                                                            #
#   1. Every file shipped in src/just_bashit/ is named somewhere in the      #
#      user-facing docs.                                                     #
#   2. Every page under docs/ is reachable from zensical.toml's nav.         #
#                                                                            #
# docs/changelog.md is excluded as a mention source. It records every script  #
# ever added, so counting it would pass every script the moment it was        #
# released — a gate that is green by construction.                           #
#                                                                            #
# Failures accumulate: both checks always run and every offender is listed,   #
# so the set gets fixed once instead of being rediscovered one push at a      #
# time.                                                                      #
# ############################################################################

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

rc=0

# ---------------------------------------------------------------------------
# 1. Shipped scripts are documented.
#
# Anything a user sources or executes counts. The Python launcher shims and
# the packaged template toml do not: they are packaging plumbing, not
# something anyone reads about.
#
# find rather than `git ls-files`, so a page that exists but is not yet staged
# still counts — a gate that fails until you `git add` reads as noise. Under
# pre-commit this is moot anyway, since it stashes unstaged work first and the
# gate then sees exactly the tree being committed.
# ---------------------------------------------------------------------------
undocumented=()
while IFS= read -r path; do
	name="${path##*/}"
	case "${name}" in
	*.py | *.toml) continue ;;
	esac
	if ! grep -rqF -- "${name}" README.md docs \
		--exclude=changelog.md 2>/dev/null; then
		undocumented+=("${name}")
	fi
done < <(find src/just_bashit -type f)

if ((${#undocumented[@]} > 0)); then
	echo "ERROR: shipped scripts documented nowhere under docs/:"
	printf '  %s\n' "${undocumented[@]}"
	echo "  Add a page (docs/libraries/NAME.md for a sourced library,"
	echo "  docs/NAME.md for a command) and list it in zensical.toml nav."
	rc=1
fi

# ---------------------------------------------------------------------------
# 2. Pages are reachable.
#
# A page absent from nav builds fine and is even served, so nothing fails —
# it is simply unlinked, which from the outside looks the same as never
# having been written. Nav paths are relative to docs/, so the prefix is
# stripped before looking each one up.
# ---------------------------------------------------------------------------
unlisted=()
while IFS= read -r page; do
	if ! grep -qF -- "\"${page#docs/}\"" zensical.toml; then
		unlisted+=("${page}")
	fi
done < <(find docs -name '*.md')

if ((${#unlisted[@]} > 0)); then
	echo "ERROR: docs pages missing from zensical.toml nav:"
	printf '  %s\n' "${unlisted[@]}"
	rc=1
fi

if ((rc == 0)); then
	echo "docs-coverage: every shipped script documented, every page in nav"
fi

exit "${rc}"
