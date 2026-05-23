load 'test_helper/common-setup'
_common_setup

GROUPED_TOML=$(
	cat <<'EOF'
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
)

INLINE_TOML=$(
	cat <<'EOF'
[runtime.apt]
packages = ["curl", "wget", "git"]
EOF
)

EMPTY_SECTION_TOML=$(
	cat <<'EOF'
[runtime.apt]
packages = []
EOF
)

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
	run bash -c "echo '${GROUPED_TOML}' | install-deps.sh --dry-run -s apt"
	assert_success
	assert_output --partial "apt-get install"
}

@test '--verbose prints section and groups' {
	run bash -c "echo '${GROUPED_TOML}' | install-deps.sh --dry-run --verbose -s apt"
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

@test 'dry run runtime group via stdin' {
	run bash -c "echo '${GROUPED_TOML}' | install-deps.sh -n -s apt"
	assert_success
	assert_output --partial "apt-get install"
	assert_output --partial "curl"
	assert_output --partial "wget"
}

@test 'dry run inline array via stdin' {
	run bash -c "echo '${INLINE_TOML}' | install-deps.sh -n -s apt"
	assert_success
	assert_output --partial "apt-get install"
	assert_output --partial "curl"
	assert_output --partial "wget"
	assert_output --partial "git"
}

@test 'dry run dev group' {
	run bash -c "echo '${GROUPED_TOML}' | install-deps.sh -n -s apt -g dev"
	assert_success
	assert_output --partial "apt-get install"
	assert_output --partial "git"
	assert_output --partial "make"
}

@test 'dry run multiple groups runtime,dev' {
	run bash -c "echo '${GROUPED_TOML}' | install-deps.sh -n -s apt -g runtime,dev"
	assert_success
	assert_output --partial "curl"
	assert_output --partial "git"
}

@test 'dry run pacman section' {
	run bash -c "echo '${GROUPED_TOML}' | install-deps.sh -n -s pacman"
	assert_success
	assert_output --partial "pacman"
	assert_output --partial "curl"
}

@test 'dry run brew section' {
	run bash -c "echo '${GROUPED_TOML}' | install-deps.sh -n -s brew"
	assert_success
	assert_output --partial "brew install"
	assert_output --partial "curl"
}

@test 'dry run from file' {
	local tmpfile
	tmpfile=$(mktemp)
	echo "${GROUPED_TOML}" >"${tmpfile}"
	run install-deps.sh -n -s apt "${tmpfile}"
	rm -f "${tmpfile}"
	assert_success
	assert_output --partial "curl"
}

@test 'error on missing group' {
	run bash -c "echo '${GROUPED_TOML}' | install-deps.sh -n -s apt -g test"
	assert_failure
	assert_output --partial "no packages found"
}

@test 'error on missing section' {
	run bash -c "echo '${GROUPED_TOML}' | install-deps.sh -n -s dnf"
	assert_failure
	assert_output --partial "no packages found"
}

@test 'error on empty packages array' {
	run bash -c "echo '${EMPTY_SECTION_TOML}' | install-deps.sh -n -s apt"
	assert_failure
	assert_output --partial "no packages found"
}

@test 'msys2 section always prints instructions' {
	run bash -c "printf '[runtime.msys2]\npackages = [\"cmake\"]\n' | install-deps.sh -s msys2"
	assert_success
	assert_output --partial "UCRT64"
	assert_output --partial "cmake"
}
