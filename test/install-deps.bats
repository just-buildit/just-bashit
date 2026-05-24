load 'test_helper/common-setup'
_common_setup

setup() {
	GROUPED_FILE="${BATS_TEST_TMPDIR}/grouped.toml"
	INLINE_FILE="${BATS_TEST_TMPDIR}/inline.toml"
	EMPTY_FILE="${BATS_TEST_TMPDIR}/empty.toml"

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
	assert_output --partial "no packages found"
}

@test 'error on missing section' {
	run install-deps.sh -n -s dnf "${GROUPED_FILE}"
	assert_failure
	assert_output --partial "no packages found"
}

@test 'error on empty packages array' {
	run install-deps.sh -n -s apt "${EMPTY_FILE}"
	assert_failure
	assert_output --partial "no packages found"
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
	run bash -c "cd '${tmpdir}' && install-deps.sh -n -s apt <'${GROUPED_FILE}'"
	assert_success
	assert_output --partial "curl"
}

@test 'auto-discovers jb-deps.toml in CWD' {
	local tmpdir="${BATS_TEST_TMPDIR}/autodiscover"
	mkdir -p "${tmpdir}"
	printf '[runtime.apt]\npackages = ["curl"]\n' >"${tmpdir}/jb-deps.toml"
	run bash -c "cd '${tmpdir}' && install-deps.sh -n -s apt"
	assert_success
	assert_output --partial "curl"
}

@test 'auto-discovers jb.toml in CWD' {
	local tmpdir="${BATS_TEST_TMPDIR}/autodiscover_jbtoml"
	mkdir -p "${tmpdir}"
	printf '[runtime.apt]\npackages = ["curl"]\n' >"${tmpdir}/jb.toml"
	run bash -c "cd '${tmpdir}' && install-deps.sh -n -s apt"
	assert_success
	assert_output --partial "curl"
}

@test 'jb-deps.toml takes priority over jb.toml' {
	local tmpdir="${BATS_TEST_TMPDIR}/priority"
	mkdir -p "${tmpdir}"
	printf '[runtime.apt]\npackages = ["curl"]\n' >"${tmpdir}/jb-deps.toml"
	printf '[runtime.apt]\npackages = ["wget"]\n' >"${tmpdir}/jb.toml"
	run bash -c "cd '${tmpdir}' && install-deps.sh -n -s apt"
	assert_success
	assert_output --partial "curl"
	refute_output --partial "wget"
}

@test 'falls back to stdin when no file present' {
	local tmpdir="${BATS_TEST_TMPDIR}/nofile"
	mkdir -p "${tmpdir}"
	run bash -c "cd '${tmpdir}' && install-deps.sh -n -s apt <'${INLINE_FILE}'"
	assert_success
	assert_output --partial "curl"
}
