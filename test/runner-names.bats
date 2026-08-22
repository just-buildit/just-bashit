# shellcheck disable=SC2154  # bats/common-setup export the harness vars
load 'test_helper/common-setup'
_common_setup

# The runner answers to `just-runit` and `jbx`, and to NOTHING ELSE.
#
# It used to answer to `jb` and `just-buildit` as well, which put one token on
# three things at once: the GitHub org, the PEP 517 build backend, and this
# script. `bootstrap.toml` was named after the wrong half of that collision.
#
# The two surviving names are not interchangeable, and the difference is the
# point: the FULL name takes subcommands and falls through to a SPEC when the
# first argument is not one; `jbx` never takes subcommands, so a script
# genuinely named `install` stays reachable as `jbx install`.

_runner_as() { # $1 = name to invoke it under; rest = args
	local name="${1}"
	shift
	local dir="${BATS_TEST_TMPDIR}/as_${name}"
	mkdir -p "${dir}"
	cp "${JB_SRC_DIR:-${BATS_TEST_DIRNAME}/../src/just_bashit}/just-runit" \
		"${dir}/${name}"
	chmod +x "${dir}/${name}"
	"${dir}/${name}" "$@"
}

@test 'just-runit takes subcommands' {
	run just-runit version
	assert_success
	assert_output --partial "just-runit v"
}

@test 'just-runit falls through to the SPEC runner for a non-subcommand' {
	# A bogus SPEC must reach the fetcher and fail there — NOT be rejected as
	# an unknown subcommand. This is what every existing caller relies on.
	run just-runit "https://just-buildit.github.io/__no_such_script__.sh"
	assert_failure
	refute_output --partial "unknown command"
}

@test 'jbx does NOT take subcommands — it treats them as a SPEC' {
	# The escape hatch: `install` as a SPEC, not the subcommand. It should
	# fail as a failed fetch, not succeed as a subcommand.
	run _runner_as jbx version
	assert_failure
	refute_output --partial "just-runit v"
}

@test 'jb is not a runner name any more' {
	run _runner_as jb version
	assert_failure
	refute_output --partial "just-runit v"
}

@test 'just-buildit is not a runner name any more' {
	run _runner_as just-buildit version
	assert_failure
	refute_output --partial "just-runit v"
}
