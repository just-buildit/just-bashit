# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, PROJECT_ROOT set by bats/common-setup
load 'test_helper/common-setup'
_common_setup

# gh-248: `--` ends option parsing, and what follows is positional. A
# getopts parser gets that for free; a hand-written `while [[ $# -gt 0 ]]`
# loop over `case "$1"` does not, and install-deps.sh read `--` as an
# unknown option. This holds every such loop in src/just_bashit -- found,
# not listed, so a new script's parser is held the moment it exists -- to
# carrying a `--)` arm. What each arm DOES is held beside the script's
# other parsing tests: `-- X` parses as `X` alone.

@test 'gh-248: every hand-written option loop has a -- arm' {
	run awk '
		FNR == 1 { inloop = 0 }
		/^[[:space:]]*while \[\[ \$# -gt 0 \]\]; do$/ {
			inloop = 1; seen = 0; start = FNR; loops++
			match($0, /^[[:space:]]*/); indent = substr($0, 1, RLENGTH)
			next
		}
		inloop && /^[[:space:]]*--\)/ { seen = 1 }
		inloop && $0 == indent "done" {
			if (!seen) print "no -- arm: " FILENAME ":" start
			inloop = 0
		}
		END { print "loops " loops + 0 }
	' "${PROJECT_ROOT}"/src/just_bashit/*
	assert_success
	refute_output --partial 'no -- arm'
	# The scan saw loops at all, so a pattern that stopped matching cannot
	# pass as "none missing".
	[[ ${lines[-1]} =~ ^loops\ ([0-9]+)$ ]] || fail "${output}"
	((BASH_REMATCH[1] > 0)) || fail 'the scan found no option loop'
}
