load 'test_helper/common-setup'
_common_setup

setup() {
	DEPS_FILE="${BATS_TEST_TMPDIR}/deps.toml"
	CMD_FILE="${BATS_TEST_TMPDIR}/cmd.toml"

	cat >"${DEPS_FILE}" <<'EOF'
[runtime.apt]
packages = ["curl", "wget"]

[dev.apt]
packages = ["git"]
EOF

	cat >"${CMD_FILE}" <<'EOF'
[runtime.apt]
cmd = ["echo", "custom-install"]

[dev.apt]
packages = ["git"]
EOF
}

@test 'inspect.sh help -h' {
	run inspect.sh -h
	assert_output --regexp "${HELP_REGEX}"
}

@test 'inspect.sh unknown option' {
	run inspect.sh -z
	assert_failure
	assert_output --regexp "Invalid option: -z"
}

@test 'output contains [system] section' {
	run inspect.sh -s apt "${DEPS_FILE}"
	assert_success
	assert_output --partial "[system]"
	assert_output --partial "os ="
	assert_output --partial "kernel ="
	assert_output --partial "arch ="
}

@test 'output contains [compiler] section' {
	run inspect.sh -s apt "${DEPS_FILE}"
	assert_success
	assert_output --partial "[compiler]"
}

@test 'output contains package section header' {
	run inspect.sh -s apt "${DEPS_FILE}"
	assert_success
	assert_output --partial "[runtime.apt]"
}

@test 'output is valid toml header comment' {
	run inspect.sh -s apt "${DEPS_FILE}"
	assert_success
	assert_output --partial "# jb.versions"
}

@test 'installed packages appear in output' {
	run inspect.sh -s apt "${DEPS_FILE}"
	assert_success
	# packages appear either with a version or as a "not installed" comment
	assert_output --regexp '(curl = "[^"]+|# curl = not installed)'
}

@test '-g restricts groups reported' {
	run inspect.sh -s apt -g runtime "${DEPS_FILE}"
	assert_success
	assert_output --partial "[runtime.apt]"
	refute_output --partial "[dev.apt]"
}

@test 'all groups reported by default' {
	run inspect.sh -s apt "${DEPS_FILE}"
	assert_success
	assert_output --partial "[runtime.apt]"
	assert_output --partial "[dev.apt]"
}

@test 'cmd sections noted, not queried' {
	run inspect.sh -s apt "${CMD_FILE}"
	assert_success
	assert_output --partial "[runtime.apt]"
	assert_output --partial "# cmd ="
	assert_output --partial "versions not queried"
}

@test 'cmd section does not show package versions' {
	run inspect.sh -s apt "${CMD_FILE}"
	assert_success
	refute_output --partial "curl ="
}

@test '-w writes jb.versions file' {
	local out="${BATS_TEST_TMPDIR}/test.versions"
	run inspect.sh -s apt -w "${out}" "${DEPS_FILE}"
	assert_success
	assert [ -f "${out}" ]
	run grep -q "\[system\]" "${out}"
	assert_success
}

@test 'auto-discovers jb.toml in CWD' {
	local tmpdir="${BATS_TEST_TMPDIR}/autodiscover"
	mkdir -p "${tmpdir}"
	printf '[runtime.apt]\npackages = ["curl"]\n' >"${tmpdir}/jb.toml"
	run bash -c "cd '${tmpdir}' && inspect.sh -s apt"
	assert_success
	assert_output --partial "[runtime.apt]"
}

@test '[tools.inspect].groups restricts default groups' {
	local f="${BATS_TEST_TMPDIR}/with_tool_groups.toml"
	cat >"${f}" <<'EOF'
[tools.inspect]
source = "just-bashit:inspect"
groups = ["runtime"]

[runtime.apt]
packages = ["curl"]

[dev.apt]
packages = ["git"]
EOF
	run inspect.sh -s apt "${f}"
	assert_success
	assert_output --partial "[runtime.apt]"
	refute_output --partial "[dev.apt]"
}
