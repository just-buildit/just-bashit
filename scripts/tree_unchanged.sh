#!/usr/bin/env bash
# ############################################################################
# tree_unchanged.sh -- repo gate, not a shipped library.                     #
# ############################################################################
# Usage: tree_unchanged.sh COMMAND [ARG...]                                  #
#                                                                            #
# Runs COMMAND and fails if it changed the working tree. A test run must     #
# leave the tree as it found it, and once did not: a cleanup line in the     #
# Makefile globbed bats-*/*.json and deleted the package.json both bats      #
# submodules track, so every `make test` left them dirty (#111).             #
#                                                                            #
# It compares `git status` before and after rather than requiring it empty, #
# so it holds on a working tree with edits in it, and                        #
# --ignore-submodules=none makes it look inside the submodules, where that   #
# damage was. The snapshot is a shell variable, so the gate itself writes    #
# nothing anywhere a status could report.                                    #
#                                                                            #
# The after-diff runs whether COMMAND passed or failed (#113): a run that    #
# fails AND dirties the tree reports both. The exit status is COMMAND's when #
# it failed, 1 when it passed and the tree changed, 0 otherwise.             #
#                                                                            #
# One definition for every command that runs the suite -- `make test`,       #
# `make test-fast` and `make coverage` all call it -- so the three cannot    #
# disagree about what "left the tree alone" means.                           #
# ############################################################################

set -uo pipefail

if [[ $# -eq 0 ]]; then
	echo "usage: tree_unchanged.sh COMMAND [ARG...]" >&2
	exit 2
fi

_status() {
	git status --porcelain --ignore-submodules=none
}

if ! before="$(_status)"; then
	echo "tree_unchanged: the tree is checked with git, and git cannot" \
		"read this checkout (its message is above)" >&2
	exit 1
fi

rc=0
"$@" || rc=$?

if ! after="$(_status)"; then
	echo "tree_unchanged: git could not read the tree after the run" \
		"(its message is above)" >&2
	exit $((rc != 0 ? rc : 1))
fi

if [[ ${before} != "${after}" ]]; then
	diff <(printf '%s\n' "${before}") <(printf '%s\n' "${after}") >&2
	echo "tree_unchanged: '$*' changed the working tree (diff above)" >&2
	exit $((rc != 0 ? rc : 1))
fi

exit "${rc}"
