# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, HELP_REGEX set by bats/common-setup
load 'test_helper/common-setup'
source 'src/just_bashit/toml.sh'
_common_setup

# ---------------------------------------------------------------------------
# toml_strings
# ---------------------------------------------------------------------------

@test 'toml_strings extracts single value' {
	run bash -c 'source src/just_bashit/toml.sh; toml_strings "\"curl\""'
	assert_success
	assert_output 'curl'
}

@test 'toml_strings extracts multiple values' {
	run bash -c 'source src/just_bashit/toml.sh; toml_strings "\"curl\", \"wget\""'
	assert_success
	assert_output "$(printf 'curl\nwget')"
}

@test 'toml_strings returns nothing for empty input' {
	run bash -c 'source src/just_bashit/toml.sh; toml_strings ""'
	assert_success
	assert_output ''
}

@test 'toml_strings skips empty quoted strings' {
	run bash -c 'source src/just_bashit/toml.sh; toml_strings "\"\", \"wget\""'
	assert_success
	assert_output 'wget'
}

# ---------------------------------------------------------------------------
# toml_get_packages
# ---------------------------------------------------------------------------

@test 'toml_get_packages inline array' {
	run bash -c '
		source src/just_bashit/toml.sh
		printf "[runtime.apt]\npackages = [\"curl\", \"wget\"]\n" \
			| toml_get_packages runtime apt
	'
	assert_success
	assert_output "$(printf 'curl\nwget')"
}

@test 'toml_get_packages multiline array' {
	run bash -c '
		source src/just_bashit/toml.sh
		printf "[runtime.apt]\npackages = [\n    \"curl\",\n    \"wget\",\n]\n" \
			| toml_get_packages runtime apt
	'
	assert_success
	assert_output "$(printf 'curl\nwget')"
}

@test 'toml_get_packages empty array returns nothing' {
	run bash -c '
		source src/just_bashit/toml.sh
		printf "[runtime.apt]\npackages = []\n" \
			| toml_get_packages runtime apt
	'
	assert_success
	assert_output ''
}

@test 'toml_get_packages only reads the right section' {
	run bash -c '
		source src/just_bashit/toml.sh
		printf "[runtime.apt]\npackages = [\"curl\"]\n[dev.apt]\npackages = [\"git\"]\n" \
			| toml_get_packages runtime apt
	'
	assert_success
	assert_output 'curl'
	refute_output 'git'
}

@test 'toml_get_packages stops at next section header' {
	run bash -c '
		source src/just_bashit/toml.sh
		printf "[runtime.apt]\npackages = [\"curl\"]\n[dev.apt]\npackages = [\"git\"]\n" \
			| toml_get_packages dev apt
	'
	assert_success
	assert_output 'git'
	refute_output 'curl'
}

@test 'toml_get_packages handles version-pinned package' {
	run bash -c '
		source src/just_bashit/toml.sh
		printf "[runtime.apt]\npackages = [\"libzmq3-dev=4.3.4-1\"]\n" \
			| toml_get_packages runtime apt
	'
	assert_success
	assert_output 'libzmq3-dev=4.3.4-1'
}

@test 'toml_get_packages returns nothing when section absent' {
	run bash -c '
		source src/just_bashit/toml.sh
		printf "[dev.apt]\npackages = [\"git\"]\n" \
			| toml_get_packages runtime apt
	'
	assert_success
	assert_output ''
}

# ---------------------------------------------------------------------------
# toml_get_cmd
# ---------------------------------------------------------------------------

@test 'toml_get_cmd inline array' {
	run bash -c '
		source src/just_bashit/toml.sh
		printf "[runtime.apt]\ncmd = [\"echo\", \"hello\"]\n" \
			| toml_get_cmd runtime apt
	'
	assert_success
	assert_output "$(printf 'echo\nhello')"
}

@test 'toml_get_cmd multiline array' {
	run bash -c '
		source src/just_bashit/toml.sh
		printf "[runtime.apt]\ncmd = [\n    \"sudo\",\n    \"apt-get\",\n    \"install\",\n]\n" \
			| toml_get_cmd runtime apt
	'
	assert_success
	assert_output "$(printf 'sudo\napt-get\ninstall')"
}

@test 'toml_get_cmd returns nothing when key absent' {
	run bash -c '
		source src/just_bashit/toml.sh
		printf "[runtime.apt]\npackages = [\"curl\"]\n" \
			| toml_get_cmd runtime apt
	'
	assert_success
	assert_output ''
}

# ---------------------------------------------------------------------------
# toml_get_tool_groups
# ---------------------------------------------------------------------------

@test 'toml_get_tool_groups inline array' {
	run bash -c '
		source src/just_bashit/toml.sh
		printf "[tools.install-deps]\ngroups = [\"runtime\", \"dev\"]\n" \
			| toml_get_tool_groups install-deps
	'
	assert_success
	assert_output 'runtime,dev'
}

@test 'toml_get_tool_groups multiline array' {
	run bash -c '
		source src/just_bashit/toml.sh
		printf "[tools.install-deps]\ngroups = [\n    \"runtime\",\n]\n" \
			| toml_get_tool_groups install-deps
	'
	assert_success
	assert_output 'runtime'
}

@test 'toml_get_tool_groups returns nothing when absent' {
	run bash -c '
		source src/just_bashit/toml.sh
		printf "[runtime.apt]\npackages = [\"curl\"]\n" \
			| toml_get_tool_groups install-deps
	'
	assert_success
	assert_output ''
}

@test 'toml_get_tool_groups reads the right tool section' {
	run bash -c '
		source src/just_bashit/toml.sh
		printf "[tools.install-deps]\ngroups = [\"runtime\"]\n[tools.inspect]\ngroups = [\"dev\"]\n" \
			| toml_get_tool_groups inspect
	'
	assert_success
	assert_output 'dev'
	refute_output 'runtime'
}

# ---------------------------------------------------------------------------
# toml_discover_groups
# ---------------------------------------------------------------------------

@test 'toml_discover_groups finds apt groups' {
	run bash -c '
		source src/just_bashit/toml.sh
		printf "[runtime.apt]\npackages = [\"curl\"]\n[dev.apt]\npackages = [\"git\"]\n" \
			| toml_discover_groups
	'
	assert_success
	assert_output 'runtime,dev'
}

@test 'toml_discover_groups preserves file order' {
	run bash -c '
		source src/just_bashit/toml.sh
		printf "[zzz.apt]\npackages = [\"a\"]\n[aaa.apt]\npackages = [\"b\"]\n" \
			| toml_discover_groups
	'
	assert_success
	assert_output 'zzz,aaa'
}

@test 'toml_discover_groups deduplicates groups across PMs' {
	run bash -c '
		source src/just_bashit/toml.sh
		printf "[runtime.apt]\npackages = [\"curl\"]\n[runtime.pacman]\npackages = [\"curl\"]\n" \
			| toml_discover_groups
	'
	assert_success
	assert_output 'runtime'
}

@test 'toml_discover_groups ignores non-PM sections' {
	run bash -c '
		source src/just_bashit/toml.sh
		printf "[tools.install-deps]\nsource = \"x\"\n[runtime.apt]\npackages = [\"curl\"]\n" \
			| toml_discover_groups
	'
	assert_success
	assert_output 'runtime'
}

@test 'toml_discover_groups ignores three-level sections' {
	run bash -c '
		source src/just_bashit/toml.sh
		printf "[a.b.apt]\npackages = [\"curl\"]\n[runtime.apt]\npackages = [\"git\"]\n" \
			| toml_discover_groups
	'
	assert_success
	assert_output 'runtime'
}

@test 'toml_discover_groups accepts custom PM list' {
	run bash -c '
		source src/just_bashit/toml.sh
		printf "[runtime.mypkg]\npackages = [\"curl\"]\n[dev.apt]\npackages = [\"git\"]\n" \
			| toml_discover_groups mypkg
	'
	assert_success
	assert_output 'runtime'
	refute_output 'dev'
}

@test 'toml_discover_groups returns empty when no PM sections' {
	run bash -c '
		source src/just_bashit/toml.sh
		printf "[project]\nname = \"test\"\n" \
			| toml_discover_groups
	'
	assert_success
	assert_output ''
}

# ---------------------------------------------------------------------------
# -h / help for all functions
# ---------------------------------------------------------------------------

@test 'toml_strings -h shows usage' {
	run bash -c 'source src/just_bashit/toml.sh; toml_strings -h'
	assert_success
	assert_output --regexp "${HELP_REGEX}"
}

@test 'toml_get_array -h shows usage' {
	run bash -c 'source src/just_bashit/toml.sh; toml_get_array -h'
	assert_success
	assert_output --regexp "${HELP_REGEX}"
}

@test 'toml_get_packages -h shows usage' {
	run bash -c 'source src/just_bashit/toml.sh; toml_get_packages -h'
	assert_success
	assert_output --regexp "${HELP_REGEX}"
}

@test 'toml_get_cmd -h shows usage' {
	run bash -c 'source src/just_bashit/toml.sh; toml_get_cmd -h'
	assert_success
	assert_output --regexp "${HELP_REGEX}"
}

@test 'toml_get_tool_groups -h shows usage' {
	run bash -c 'source src/just_bashit/toml.sh; toml_get_tool_groups -h'
	assert_success
	assert_output --regexp "${HELP_REGEX}"
}

@test 'toml_discover_groups -h shows usage' {
	run bash -c 'source src/just_bashit/toml.sh; toml_discover_groups -h'
	assert_success
	assert_output --regexp "${HELP_REGEX}"
}
