# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, HELP_REGEX set by bats/common-setup
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
	cd "${tmpdir}"
	run inspect.sh -s apt
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

@test 'reads from stdin when no file in CWD' {
	local tmpdir="${BATS_TEST_TMPDIR}/stdin_inspect"
	mkdir -p "${tmpdir}"
	cd "${tmpdir}"
	run inspect.sh -s apt <"${DEPS_FILE}"
	assert_success
	assert_output --partial "[runtime.apt]"
}

@test 'jb-deps.toml takes priority over jb.toml' {
	local tmpdir="${BATS_TEST_TMPDIR}/inspect_priority"
	mkdir -p "${tmpdir}"
	printf '[runtime.apt]\npackages = ["curl"]\n' >"${tmpdir}/jb-deps.toml"
	printf '[runtime.apt]\npackages = ["wget"]\n' >"${tmpdir}/jb.toml"
	cd "${tmpdir}"
	run inspect.sh -s apt
	assert_success
	assert_output --partial "curl"
	refute_output --partial "wget"
}

@test '-v verbose output goes to stderr' {
	run inspect.sh -v -s apt "${DEPS_FILE}"
	assert_success
	# bats captures stderr in $output when using run without --separate-stderr
	assert_output --partial "section:"
	assert_output --partial "groups:"
}

@test '-w writes file and also outputs to stdout' {
	local out="${BATS_TEST_TMPDIR}/tee_test.versions"
	run inspect.sh -s apt -w "${out}" "${DEPS_FILE}"
	assert_success
	assert [ -f "${out}" ]
	# stdout should also contain the content (tee behavior)
	assert_output --partial "[system]"
}

@test 'output contains glibc on linux' {
	if [[ "$(uname -s)" != "Linux" ]] ||
		grep -qi musl /proc/version 2>/dev/null ||
		grep -qi alpine /etc/os-release 2>/dev/null; then
		skip "glibc only on glibc Linux"
	fi
	run inspect.sh -s apt "${DEPS_FILE}"
	assert_success
	assert_output --partial "glibc"
}

@test 'not-installed packages shown as comments' {
	local f="${BATS_TEST_TMPDIR}/notinstalled.toml"
	printf '[runtime.apt]\npackages = ["this-package-does-not-exist-xyzzy"]\n' >"${f}"
	run inspect.sh -s apt "${f}"
	assert_success
	assert_output --partial "# this-package-does-not-exist-xyzzy = not installed"
}

@test '-g with comma-separated groups reports both' {
	run inspect.sh -s apt -g runtime,dev "${DEPS_FILE}"
	assert_success
	assert_output --partial "[runtime.apt]"
	assert_output --partial "[dev.apt]"
}

@test 'long form --section works' {
	run inspect.sh --section apt "${DEPS_FILE}"
	assert_success
	assert_output --partial "[runtime.apt]"
}

@test 'long form --groups restricts output' {
	run inspect.sh --section apt --groups runtime "${DEPS_FILE}"
	assert_success
	assert_output --partial "[runtime.apt]"
	refute_output --partial "[dev.apt]"
}

@test 'long form --verbose emits section and groups to stderr' {
	run inspect.sh --verbose --section apt "${DEPS_FILE}"
	assert_success
	assert_output --partial "section:"
}

@test 'long form --write with explicit path' {
	local out="${BATS_TEST_TMPDIR}/longform.versions"
	run inspect.sh --section apt --write "${out}" "${DEPS_FILE}"
	assert_success
	assert [ -f "${out}" ]
}

@test '-w without filename defaults to jb.versions in CWD' {
	cp "${DEPS_FILE}" "${BATS_TEST_TMPDIR}/jb-deps.toml"
	cd "${BATS_TEST_TMPDIR}"
	run inspect.sh -s apt -w
	assert_success
	assert [ -f "${BATS_TEST_TMPDIR}/jb.versions" ]
}

@test '-w prints wrote message to stderr' {
	local out="${BATS_TEST_TMPDIR}/wrote_msg.versions"
	run inspect.sh -s apt -w "${out}" "${DEPS_FILE}"
	assert_success
	assert_output --partial "wrote"
}

@test 'file with no matching PM sections outputs system and compiler only' {
	local f="${BATS_TEST_TMPDIR}/nopm.toml"
	printf '[project]\nname = "test"\n' >"${f}"
	run inspect.sh -s apt "${f}"
	assert_success
	assert_output --partial "[system]"
	assert_output --partial "[compiler]"
	refute_output --partial "[runtime"
	refute_output --partial "[dev"
}

@test '-s pacman queries pacman packages' {
	if ! command -v pacman >/dev/null 2>&1; then
		skip "pacman not available"
	fi
	local f="${BATS_TEST_TMPDIR}/pacman.toml"
	printf '[runtime.pacman]\npackages = ["bash"]\n' >"${f}"
	run inspect.sh -s pacman "${f}"
	assert_success
	assert_output --partial "[runtime.pacman]"
	assert_output --regexp '(bash = "[^"]+|# bash = not installed)'
}

@test 'auto-detects package manager when no -s given' {
	local f="${BATS_TEST_TMPDIR}/autodetect.toml"
	cat >"${f}" <<'EOF'
[runtime.apt]
packages = ["bash"]

[runtime.pacman]
packages = ["bash"]

[runtime.brew]
packages = ["bash"]

[runtime.dnf]
packages = ["bash"]
EOF
	run inspect.sh "${f}"
	assert_success
	assert_output --partial "[system]"
}

@test 'explicit -g overrides [tools.inspect].groups' {
	local f="${BATS_TEST_TMPDIR}/override_inspect.toml"
	cat >"${f}" <<'EOF'
[tools.inspect]
groups = ["runtime"]

[runtime.apt]
packages = ["curl"]

[dev.apt]
packages = ["git"]
EOF
	run inspect.sh -s apt -g dev "${f}"
	assert_success
	assert_output --partial "[dev.apt]"
	refute_output --partial "[runtime.apt]"
}
