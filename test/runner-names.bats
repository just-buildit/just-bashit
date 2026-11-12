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

# Every fetch these tests provoke is answered offline, from an empty fixture
# directory: each one 404s, which is the failure they expect (#147).
setup() {
	mkdir -p "${BATS_TEST_TMPDIR}/fixtures"
	_serve_fixtures "${BATS_TEST_TMPDIR}/fixtures"
}

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

# ---------------------------------------------------------------------------
# Help. `jbx -h` printed its usage line twice, `jbx --help` was refused as
# an invalid option (exit 1), and `jbx help` -- a SPEC, since jbx takes no
# subcommands -- failed resolving with no word about -h.
# ---------------------------------------------------------------------------

@test 'jbx -h shows its usage once; just-runit run -h shows the jbx spelling too' {
	run _runner_as jbx -h
	assert_success
	run grep -c 'jbx \[OPTIONS\] SPEC' <<<"${output}"
	assert_output 1
	run just-runit run -h
	assert_success
	assert_line --index 0 'Usage: just-runit run [OPTIONS] SPEC [FUNCTION [ARGS...]]'
	assert_line --index 1 '   or: jbx [OPTIONS] SPEC [FUNCTION [ARGS...]]'
}

@test 'jbx --help is -h' {
	run _runner_as jbx -h
	local short="${output}"
	run _runner_as jbx --help
	assert_success
	assert_output "${short}"
}

@test '--help after SPEC is the script'"'"'s, not jbx'"'"'s' {
	printf '%s\n' 'echo "script got [$*]"' >"${BATS_TEST_TMPDIR}/fixtures/t.sh"
	run _runner_as jbx -n https://example.com/t.sh --help
	assert_success
	assert_output 'script got [--help]'
}

@test 'jbx help names -h once no script called help resolves' {
	echo '[aliases]' >"${BATS_TEST_TMPDIR}/fixtures/aliases.toml"
	run _runner_as jbx -n help
	assert_failure
	assert_output --partial "no script named 'help'"
	assert_output --partial 'jbx -h'
}

@test 'jbx help runs a script that is really called help' {
	echo '[aliases]' >"${BATS_TEST_TMPDIR}/fixtures/aliases.toml"
	echo 'echo "the real help script"' >"${BATS_TEST_TMPDIR}/fixtures/help.sh"
	run _runner_as jbx -n help
	assert_success
	assert_output 'the real help script'
}

@test 'the help lists the user namespaces and points at ns add' {
	export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/config"
	just-runit ns add tools https://example.com/tools
	run _runner_as jbx -h
	assert_output --partial 'tools                 https://example.com/tools/   (yours)'
	assert_output --partial 'Add your own: just-runit ns add NAME BASE'
}
