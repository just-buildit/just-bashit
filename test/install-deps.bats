# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, HELP_REGEX set by bats/common-setup
load 'test_helper/common-setup'
_common_setup

setup() {
	GROUPED_FILE="${BATS_TEST_TMPDIR}/grouped.toml"
	INLINE_FILE="${BATS_TEST_TMPDIR}/inline.toml"
	EMPTY_FILE="${BATS_TEST_TMPDIR}/empty.toml"
	ALL_PM_FILE="${BATS_TEST_TMPDIR}/all_pm.toml"
	PINNED_FILE="${BATS_TEST_TMPDIR}/pinned.toml"

	cat >"${GROUPED_FILE}" <<'EOF'
[runtime.apt]
packages = [
    "curl",
    "wget",
]

[runtime.pacman]
packages = ["curl", "wget"]

[runtime.brew]
packages = [
    "curl",
]

[dev.apt]
packages = ["git", "make"]

[dev.pacman]
packages = ["git", "make"]
EOF

	cat >"${INLINE_FILE}" <<'EOF'
[runtime.apt]
packages = ["curl", "wget", "git"]
EOF

	cat >"${EMPTY_FILE}" <<'EOF'
[runtime.apt]
packages = []
EOF

	cat >"${ALL_PM_FILE}" <<'EOF'
[runtime.apt]
packages = ["curl"]

[runtime.pacman]
packages = ["curl"]

[runtime.brew]
packages = ["curl"]

[runtime.dnf]
packages = ["curl"]

[runtime.zypper]
packages = ["curl"]

[runtime.apk]
packages = ["curl"]

[runtime.msys2]
packages = ["curl"]
EOF

	cat >"${PINNED_FILE}" <<'EOF'
[runtime.apt]
packages = ["libzmq3-dev=4.3.4-1"]

[runtime.dnf]
packages = ["zeromq-devel-4.3.4"]
EOF
}

@test 'install-deps.sh help -h' {
	run install-deps.sh -h
	assert_output --regexp "${HELP_REGEX}"
}

@test 'install-deps.sh unknown option' {
	run install-deps.sh -z
	assert_failure
	assert_output --regexp "Invalid option: -z"
}

@test 'install-deps.sh -s option requires argument' {
	run install-deps.sh -s
	assert_failure
}

@test 'install-deps.sh -g option requires argument' {
	run install-deps.sh -g
	assert_failure
}

@test '--dry-run long form' {
	run install-deps.sh --dry-run -s apt "${GROUPED_FILE}"
	assert_success
	assert_output --partial "apt-get install"
}

@test '--verbose prints section and groups' {
	run install-deps.sh -n --verbose -s apt "${GROUPED_FILE}"
	assert_success
	assert_output --partial "section:"
	assert_output --partial "groups:"
	assert_output --partial "packages:"
}

@test '--template writes scaffold to stdout' {
	run install-deps.sh --template
	assert_success
	assert_output --partial "[runtime.apt]"
	assert_output --partial "[dev.pacman]"
	assert_output --partial "[dev.msys2]"
}

@test '--template writes scaffold to file' {
	local tmpfile
	tmpfile=$(mktemp)
	run install-deps.sh --template "${tmpfile}"
	assert_success
	run grep -q "\[runtime.apt\]" "${tmpfile}"
	assert_success
	rm -f "${tmpfile}"
}

@test 'dry run runtime group' {
	run install-deps.sh -n -s apt "${GROUPED_FILE}"
	assert_success
	assert_output --partial "apt-get install"
	assert_output --partial "curl"
	assert_output --partial "wget"
}

@test 'dry run inline array' {
	run install-deps.sh -n -s apt "${INLINE_FILE}"
	assert_success
	assert_output --partial "apt-get install"
	assert_output --partial "curl"
	assert_output --partial "wget"
	assert_output --partial "git"
}

@test 'dry run dev group' {
	run install-deps.sh -n -s apt -g dev "${GROUPED_FILE}"
	assert_success
	assert_output --partial "apt-get install"
	assert_output --partial "git"
	assert_output --partial "make"
}

@test 'dry run multiple groups runtime,dev' {
	run install-deps.sh -n -s apt -g runtime,dev "${GROUPED_FILE}"
	assert_success
	assert_output --partial "curl"
	assert_output --partial "git"
}

@test 'dry run pacman section' {
	run install-deps.sh -n -s pacman "${GROUPED_FILE}"
	assert_success
	assert_output --partial "pacman"
	assert_output --partial "curl"
}

@test 'dry run brew section' {
	run install-deps.sh -n -s brew "${GROUPED_FILE}"
	assert_success
	assert_output --partial "brew install"
	assert_output --partial "curl"
}

@test 'error on missing group' {
	run install-deps.sh -n -s apt -g test "${GROUPED_FILE}"
	assert_failure
	assert_output --partial "no packages or cmd found"
}

@test 'error on missing section' {
	run install-deps.sh -n -s dnf "${GROUPED_FILE}"
	assert_failure
	assert_output --partial "no packages or cmd found"
}

@test 'error on empty packages array' {
	run install-deps.sh -n -s apt "${EMPTY_FILE}"
	assert_failure
	assert_output --partial "no packages or cmd found"
}

@test 'msys2 section always prints instructions' {
	local msys2file="${BATS_TEST_TMPDIR}/msys2.toml"
	printf '[runtime.msys2]\npackages = ["cmake"]\n' >"${msys2file}"
	run install-deps.sh -s msys2 "${msys2file}"
	assert_success
	assert_output --partial "UCRT64"
	assert_output --partial "cmake"
}

@test 'reads from stdin when no file argument' {
	local tmpdir="${BATS_TEST_TMPDIR}/stdin_nofile"
	mkdir -p "${tmpdir}"
	cd "${tmpdir}"
	run install-deps.sh -n -s apt <"${GROUPED_FILE}"
	assert_success
	assert_output --partial "curl"
}

@test 'auto-discovers jb-deps.toml in CWD' {
	local tmpdir="${BATS_TEST_TMPDIR}/autodiscover"
	mkdir -p "${tmpdir}"
	printf '[runtime.apt]\npackages = ["curl"]\n' >"${tmpdir}/jb-deps.toml"
	cd "${tmpdir}"
	run install-deps.sh -n -s apt
	assert_success
	assert_output --partial "curl"
}

@test 'auto-discovers jb.toml in CWD' {
	local tmpdir="${BATS_TEST_TMPDIR}/autodiscover_jbtoml"
	mkdir -p "${tmpdir}"
	printf '[runtime.apt]\npackages = ["curl"]\n' >"${tmpdir}/jb.toml"
	cd "${tmpdir}"
	run install-deps.sh -n -s apt
	assert_success
	assert_output --partial "curl"
}

@test 'jb-deps.toml takes priority over jb.toml' {
	local tmpdir="${BATS_TEST_TMPDIR}/priority"
	mkdir -p "${tmpdir}"
	printf '[runtime.apt]\npackages = ["curl"]\n' >"${tmpdir}/jb-deps.toml"
	printf '[runtime.apt]\npackages = ["wget"]\n' >"${tmpdir}/jb.toml"
	cd "${tmpdir}"
	run install-deps.sh -n -s apt
	assert_success
	assert_output --partial "curl"
	refute_output --partial "wget"
}

@test 'falls back to stdin when no file present' {
	local tmpdir="${BATS_TEST_TMPDIR}/nofile"
	mkdir -p "${tmpdir}"
	cd "${tmpdir}"
	run install-deps.sh -n -s apt <"${INLINE_FILE}"
	assert_success
	assert_output --partial "curl"
}

@test 'no -g installs all groups when no toml groups key' {
	run install-deps.sh -n -s apt "${GROUPED_FILE}"
	assert_success
	assert_output --partial "curl"
	assert_output --partial "git"
}

@test '[tools.install-deps].groups restricts default groups' {
	local f="${BATS_TEST_TMPDIR}/with_tool_groups.toml"
	cat >"${f}" <<'EOF'
[tools.install-deps]
source = "just-bashit:install-deps"
groups = ["runtime"]

[runtime.apt]
packages = ["curl"]

[dev.apt]
packages = ["git"]
EOF
	run install-deps.sh -n -s apt "${f}"
	assert_success
	assert_output --partial "curl"
	refute_output --partial "git"
}

@test 'explicit -g overrides toml groups key' {
	local f="${BATS_TEST_TMPDIR}/override_groups.toml"
	cat >"${f}" <<'EOF'
[tools.install-deps]
groups = ["runtime"]

[runtime.apt]
packages = ["curl"]

[dev.apt]
packages = ["git"]
EOF
	run install-deps.sh -n -s apt -g dev "${f}"
	assert_success
	assert_output --partial "git"
	refute_output --partial "curl"
}

@test 'cmd is executed verbatim instead of pm install' {
	local f="${BATS_TEST_TMPDIR}/cmd.toml"
	printf '[runtime.apt]\ncmd = ["echo", "custom-cmd-ran"]\n' >"${f}"
	run install-deps.sh -s apt "${f}"
	assert_success
	assert_output --partial "custom-cmd-ran"
}

@test 'cmd dry-run prints the command' {
	local f="${BATS_TEST_TMPDIR}/cmd_dry.toml"
	printf '[runtime.apt]\ncmd = ["sudo", "apt-get", "install", "-y", "mypkg"]\n' >"${f}"
	run install-deps.sh -n -s apt "${f}"
	assert_success
	assert_output --partial "sudo apt-get install -y mypkg"
}

@test 'cmd takes precedence over packages in same section' {
	local f="${BATS_TEST_TMPDIR}/cmd_precedence.toml"
	cat >"${f}" <<'EOF'
[runtime.apt]
cmd = ["echo", "from-cmd"]
packages = ["curl"]
EOF
	run install-deps.sh -s apt "${f}"
	assert_success
	assert_output --partial "from-cmd"
	refute_output --partial "apt-get"
}

@test 'cmd and packages coexist across groups' {
	local f="${BATS_TEST_TMPDIR}/cmd_and_pkgs.toml"
	cat >"${f}" <<'EOF'
[runtime.apt]
cmd = ["echo", "runtime-cmd"]

[dev.apt]
packages = ["git"]
EOF
	run install-deps.sh -n -s apt "${f}"
	assert_success
	assert_output --partial "echo runtime-cmd"
	assert_output --partial "apt-get"
	assert_output --partial "git"
}

@test 'error message mentions cmd when nothing found' {
	local f="${BATS_TEST_TMPDIR}/empty_cmd.toml"
	printf '[runtime.apt]\npackages = []\n' >"${f}"
	run install-deps.sh -n -s apt -g dev "${f}"
	assert_failure
	assert_output --partial "no packages or cmd found"
}

@test 'dry run dnf section' {
	run install-deps.sh -n -s dnf "${ALL_PM_FILE}"
	assert_success
	assert_output --partial "sudo dnf install -y"
	assert_output --partial "curl"
}

@test 'dry run zypper section' {
	run install-deps.sh -n -s zypper "${ALL_PM_FILE}"
	assert_success
	assert_output --partial "sudo zypper install -y"
	assert_output --partial "curl"
}

@test 'dry run apk section' {
	run install-deps.sh -n -s apk "${ALL_PM_FILE}"
	assert_success
	assert_output --partial "sudo apk add"
	assert_output --partial "curl"
}

@test 'apt dry run includes update step' {
	run install-deps.sh -n -s apt "${ALL_PM_FILE}"
	assert_success
	assert_output --partial "apt-get update"
}

@test 'version-pinned apt package passes through verbatim' {
	run install-deps.sh -n -s apt "${PINNED_FILE}"
	assert_success
	assert_output --partial "libzmq3-dev=4.3.4-1"
}

@test 'version-pinned dnf package passes through verbatim' {
	run install-deps.sh -n -s dnf "${PINNED_FILE}"
	assert_success
	assert_output --partial "zeromq-devel-4.3.4"
}

@test 'verbose shows cmd keyword for cmd groups' {
	local f="${BATS_TEST_TMPDIR}/cmd_verbose.toml"
	printf '[runtime.apt]\ncmd = ["echo", "hi"]\n' >"${f}"
	run install-deps.sh -n -v -s apt "${f}"
	assert_success
	assert_output --partial "cmd:"
}

@test 'unknown section error' {
	local f="${BATS_TEST_TMPDIR}/bad_section.toml"
	printf '[runtime.unknownpm]\npackages = ["curl"]\n' >"${f}"
	run install-deps.sh -g runtime -s unknownpm "${f}"
	assert_failure
	assert_output --partial "unknown section"
}

@test 'template contains placeholder examples' {
	run install-deps.sh --template
	assert_success
	assert_output --partial "e.g."
	assert_output --partial "libzmq3-dev"
}

@test 'multiline packages array collects all packages' {
	run install-deps.sh -n -s apt -g runtime "${GROUPED_FILE}"
	assert_success
	assert_output --partial "curl"
	assert_output --partial "wget"
}

@test 'long form --section overrides detected PM' {
	run install-deps.sh -n --section apt "${GROUPED_FILE}"
	assert_success
	assert_output --partial "apt-get install"
}

@test 'long form --groups restricts groups' {
	run install-deps.sh -n --section apt --groups runtime "${GROUPED_FILE}"
	assert_success
	assert_output --partial "curl"
	refute_output --partial "git"
}

@test 'auto-detects package manager from OS' {
	local f="${BATS_TEST_TMPDIR}/autodetect.toml"
	# Include sections for common PMs so the test works on any platform
	cat >"${f}" <<'EOF'
[runtime.apt]
packages = ["bash"]

[runtime.pacman]
packages = ["bash"]

[runtime.brew]
packages = ["bash"]

[runtime.dnf]
packages = ["bash"]

[runtime.apk]
packages = ["bash"]

[runtime.msys2]
packages = ["bash"]
EOF
	# Run without -s so _detect_section is actually called
	run install-deps.sh -n -g runtime "${f}"
	assert_success
	assert_output --partial "bash"
}

@test '[tools.install-deps].groups multiline toml array' {
	local f="${BATS_TEST_TMPDIR}/multiline_tool_groups.toml"
	cat >"${f}" <<'EOF'
[tools.install-deps]
groups = [
    "runtime",
]

[runtime.apt]
packages = ["curl"]

[dev.apt]
packages = ["git"]
EOF
	run install-deps.sh -n -s apt "${f}"
	assert_success
	assert_output --partial "curl"
	refute_output --partial "git"
}

@test 'msys2 exits with success' {
	local f="${BATS_TEST_TMPDIR}/msys2_exit.toml"
	printf '[runtime.msys2]\npackages = ["cmake"]\n' >"${f}"
	run install-deps.sh -s msys2 "${f}"
	assert_success
}

@test 'error message includes section name' {
	run install-deps.sh -n -s apt -g test "${GROUPED_FILE}"
	assert_failure
	assert_output --partial "apt"
}

@test 'non-pm sections ignored in group discovery' {
	local f="${BATS_TEST_TMPDIR}/mixed.toml"
	cat >"${f}" <<'EOF'
[tools.install-deps]
source = "just-bashit:install-deps"

[runtime.apt]
packages = ["curl"]
EOF
	run install-deps.sh -n -s apt "${f}"
	assert_success
	assert_output --partial "curl"
	refute_output --partial "tools"
}

@test 'groups are discovered in file order' {
	local f="${BATS_TEST_TMPDIR}/ordered.toml"
	cat >"${f}" <<'EOF'
[aaa.apt]
packages = ["aaa-pkg"]

[zzz.apt]
packages = ["zzz-pkg"]
EOF
	run install-deps.sh -n -s apt "${f}"
	assert_success
	local aaa_pos zzz_pos
	aaa_pos=$(echo "${output}" | grep -n "aaa-pkg" | cut -d: -f1)
	zzz_pos=$(echo "${output}" | grep -n "zzz-pkg" | cut -d: -f1)
	assert [ "${aaa_pos}" -lt "${zzz_pos}" ]
}
