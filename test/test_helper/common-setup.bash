#!/usr/bin/env bash

_common_setup() {
	load 'test_helper/bats-support/load'
	load 'test_helper/bats-assert/load'
	# get the containing directory of this file
	# use $BATS_TEST_FILENAME instead of ${BASH_SOURCE[0]} or $0,
	# as those will point to the bats executable's location or the preprocessed file respectively
	# shellcheck disable=SC2154
	PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." >/dev/null 2>&1 && pwd)"
	# make executables in src/ visible to PATH
	PATH="$PROJECT_ROOT/src:$PATH"
	export HELP_REGEX='Usage:' # Check each script/function at least has usage.
	export BASH_XTRACEFD=2          # Redirect kcov trace lines to stderr so bats never sees them.
}
