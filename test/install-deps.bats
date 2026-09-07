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

# The sudo prefix is derived from the caller's uid, so these pin the mode
# explicitly. The same assertions without --sudo pass on a workstation and
# fail inside the root CI container -- a split this suite should catch, not
# reproduce.
@test 'dry run dnf section' {
	run install-deps.sh -n --sudo -s dnf "${ALL_PM_FILE}"
	assert_success
	assert_output --partial "sudo dnf install -y"
	assert_output --partial "curl"
}

@test 'dry run zypper section' {
	run install-deps.sh -n --sudo -s zypper "${ALL_PM_FILE}"
	assert_success
	assert_output --partial "sudo zypper install -y"
	assert_output --partial "curl"
}

@test 'dry run apk section' {
	run install-deps.sh -n --sudo -s apk "${ALL_PM_FILE}"
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

# --- bootstrap.toml (the name; jb.toml and jb-deps.toml are deprecated) ------

@test 'auto-discovers bootstrap.toml in CWD' {
	local tmpdir="${BATS_TEST_TMPDIR}/autodiscover_bootstrap"
	mkdir -p "${tmpdir}"
	printf '[runtime.apt]\npackages = ["curl"]\n' >"${tmpdir}/bootstrap.toml"
	cd "${tmpdir}"
	run install-deps.sh -n -s apt
	assert_success
	assert_output --partial "curl"
}

@test 'bootstrap.toml takes priority over both deprecated names' {
	local tmpdir="${BATS_TEST_TMPDIR}/bootstrap_priority"
	mkdir -p "${tmpdir}"
	printf '[runtime.apt]\npackages = ["curl"]\n' >"${tmpdir}/bootstrap.toml"
	printf '[runtime.apt]\npackages = ["wget"]\n' >"${tmpdir}/jb-deps.toml"
	printf '[runtime.apt]\npackages = ["nano"]\n' >"${tmpdir}/jb.toml"
	cd "${tmpdir}"
	run install-deps.sh -n -s apt
	assert_success
	assert_output --partial "curl"
	refute_output --partial "wget"
	refute_output --partial "nano"
}

@test 'bootstrap.toml is silent; the deprecated names warn' {
	local tmpdir="${BATS_TEST_TMPDIR}/deprecation_notice"
	mkdir -p "${tmpdir}/new" "${tmpdir}/old"
	printf '[runtime.apt]\npackages = ["curl"]\n' >"${tmpdir}/new/bootstrap.toml"
	printf '[runtime.apt]\npackages = ["curl"]\n' >"${tmpdir}/old/jb.toml"

	cd "${tmpdir}/new"
	run install-deps.sh -n -s apt
	assert_success
	refute_output --partial "deprecated"

	cd "${tmpdir}/old"
	run install-deps.sh -n -s apt
	assert_success
	assert_output --partial "jb.toml is deprecated"
	assert_output --partial "bootstrap.toml"
}

# ---------------------------------------------------------------------------
# sudo resolution
#
# The point of these: one bootstrap.toml has to serve a workstation (not
# root, sudo present) and a CI container (already root, no sudo package).
# The mode is derived from the environment, so each case below pins the
# environment rather than the expectation.
# ---------------------------------------------------------------------------

# Put a fake `id` ahead of the real one so the root branch is reachable from
# an unprivileged test run. `command -v sudo` is left alone -- root must not
# consult it at all.
_fake_uid() {
	local uid="$1"
	local dir="${BATS_TEST_TMPDIR}/fakebin-${uid}"
	local real_id
	# Resolve the real id now, while the real PATH is still in effect: the
	# shim runs with a PATH that deliberately excludes it.
	real_id="$(command -v id)"
	mkdir -p "${dir}"
	# shellcheck disable=SC2016  # $1 and $@ belong to the generated script
	printf '#!/bin/sh\nif [ "$1" = "-u" ]; then echo %s; else exec %s "$@"; fi\n' \
		"${uid}" "${real_id}" >"${dir}/id"
	chmod +x "${dir}/id"
	printf '%s\n' "${dir}"
}

@test '--no-sudo drops the prefix from apt' {
	run install-deps.sh -n --no-sudo -s apt "${ALL_PM_FILE}"
	assert_success
	assert_output --partial "apt-get install -y --no-install-recommends curl"
	refute_output --partial "sudo"
}

@test '--no-sudo drops the prefix from the apt update step too' {
	run install-deps.sh -n --no-sudo -s apt "${ALL_PM_FILE}"
	assert_success
	assert_line "apt-get update"
}

@test '--no-sudo drops the prefix from every root-needing manager' {
	local pm
	for pm in pacman dnf zypper apk; do
		run install-deps.sh -n --no-sudo -s "${pm}" "${ALL_PM_FILE}"
		assert_success
		refute_output --partial "sudo"
	done
}

@test '--sudo forces the prefix even when already root' {
	local bin
	bin="$(_fake_uid 0)"
	PATH="${bin}:${PATH}" run install-deps.sh -n --sudo -s apt "${ALL_PM_FILE}"
	assert_success
	assert_line "sudo apt-get update"
}

@test 'auto: root gets no sudo prefix' {
	local bin
	bin="$(_fake_uid 0)"
	PATH="${bin}:${PATH}" run install-deps.sh -n -s apt "${ALL_PM_FILE}"
	assert_success
	assert_line "apt-get update"
	refute_output --partial "sudo"
}

@test 'auto: non-root with sudo on PATH gets the prefix' {
	local bin
	bin="$(_fake_uid 1000)"
	# A stub sudo makes the `command -v sudo` probe true regardless of what
	# the host image actually ships.
	# shellcheck disable=SC2016  # $@ belongs to the generated script
	printf '#!/bin/sh\nexec "$@"\n' >"${bin}/sudo"
	chmod +x "${bin}/sudo"
	PATH="${bin}:${PATH}" run install-deps.sh -n -s apt "${ALL_PM_FILE}"
	assert_success
	assert_line "sudo apt-get update"
}

@test 'auto: non-root without sudo warns and runs bare' {
	local bin dir tool
	bin="$(_fake_uid 1000)"
	# A PATH holding only what the script itself needs -- and no sudo -- so
	# the `command -v sudo` probe genuinely fails. Emptying PATH instead
	# would lose bash and test nothing.
	dir="${BATS_TEST_TMPDIR}/nosudo"
	mkdir -p "${dir}"
	cp "${bin}/id" "${dir}/id"
	for tool in bash cat dirname head pwd tr uname; do
		ln -sf "$(command -v "${tool}")" "${dir}/${tool}"
	done
	run env -i PATH="${dir}" HOME="${HOME}" \
		"${dir}/bash" "${PROJECT_ROOT}/src/just_bashit/install-deps.sh" \
		-n -s apt "${ALL_PM_FILE}"
	assert_success
	assert_output --partial "sudo not found"
	assert_line "apt-get update"
}

@test 'brew never gets a sudo prefix, even with --sudo' {
	run install-deps.sh -n --sudo -s brew "${ALL_PM_FILE}"
	assert_success
	assert_line "brew install curl"
	refute_output --partial "sudo"
}

@test 'sudo mode does not touch verbatim cmd arrays' {
	local f="${BATS_TEST_TMPDIR}/cmd_nosudo.toml"
	printf '[runtime.apt]\ncmd = ["apt-get", "install", "-y", "mypkg"]\n' >"${f}"
	run install-deps.sh -n --sudo -s apt "${f}"
	assert_success
	assert_line "apt-get install -y mypkg"
	refute_output --partial "sudo"
}

@test 'help documents both sudo flags' {
	run install-deps.sh --help
	assert_success
	assert_output --partial "--no-sudo"
	assert_output --partial "--sudo"
}

# ---------------------------------------------------------------------------
# proxy
#
# Every test here clears the ambient proxy variables first: a developer
# machine behind a corporate proxy would otherwise pass or fail these for
# reasons that have nothing to do with the code.
# ---------------------------------------------------------------------------

_no_proxy_env() {
	printf '%s\n' -u http_proxy -u https_proxy -u all_proxy -u no_proxy \
		-u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u NO_PROXY
}

# Run install-deps.sh with every proxy variable unset, plus any NAME=VALUE
# assignments given as leading arguments.
_run_clean() {
	local clear=()
	while IFS= read -r _a; do clear+=("${_a}"); done < <(_no_proxy_env)
	local assigns=()
	while [[ $# -gt 0 && "$1" == *=* ]]; do
		assigns+=("$1")
		shift
	done
	if [ "${#assigns[@]}" -gt 0 ]; then
		run env "${clear[@]}" "${assigns[@]}" install-deps.sh "$@"
	else
		run env "${clear[@]}" install-deps.sh "$@"
	fi
}

@test 'no proxy anywhere leaves the command untouched' {
	_run_clean -n --sudo -s apt "${ALL_PM_FILE}"
	assert_success
	assert_line "sudo apt-get update"
	refute_output --partial "env "
}

@test '--proxy lands on the far side of sudo, where env_reset cannot drop it' {
	_run_clean -n --sudo --proxy http://p.example:3128 -s apt "${ALL_PM_FILE}"
	assert_success
	# Order matters: `env A=B sudo cmd` would set the variable for sudo and
	# then have it reset away again.
	assert_line --regexp '^sudo env .*apt-get update$'
}

@test '--proxy sets both spellings of http and https' {
	_run_clean -n --no-sudo --proxy http://p.example:3128 -s apt "${ALL_PM_FILE}"
	assert_success
	assert_output --partial "http_proxy=http://p.example:3128"
	assert_output --partial "https_proxy=http://p.example:3128"
	assert_output --partial "HTTP_PROXY=http://p.example:3128"
	assert_output --partial "HTTPS_PROXY=http://p.example:3128"
}

@test '--proxy applies to every root-needing manager' {
	local pm
	for pm in apt pacman dnf zypper apk; do
		_run_clean -n --no-sudo --proxy http://p.example:3128 -s "${pm}" \
			"${ALL_PM_FILE}"
		assert_success
		assert_output --partial "env http_proxy=http://p.example:3128"
	done
}

@test '--proxy applies to brew, which still gets no sudo' {
	_run_clean -n --sudo --proxy http://p.example:3128 -s brew "${ALL_PM_FILE}"
	assert_success
	assert_line --regexp '^env .*brew install curl$'
	refute_output --partial "sudo"
}

@test 'ambient http_proxy is carried through with no flag' {
	_run_clean http_proxy=http://ambient:8080 -n --sudo -s apt "${ALL_PM_FILE}"
	assert_success
	assert_output --partial "http_proxy=http://ambient:8080"
}

@test 'ambient no_proxy and all_proxy are carried through too' {
	_run_clean http_proxy=http://ambient:8080 no_proxy=localhost,.internal \
		all_proxy=socks5://s:1080 -n --sudo -s apt "${ALL_PM_FILE}"
	assert_success
	assert_output --partial "no_proxy=localhost,.internal"
	assert_output --partial "all_proxy=socks5://s:1080"
}

@test 'no_proxy on its own does not wrap the command in env' {
	# Exceptions to a proxy that is not configured describe nothing, and
	# wrapping for them would change every command on a machine that merely
	# has no_proxy set in a shell profile.
	_run_clean no_proxy=localhost -n --sudo -s apt "${ALL_PM_FILE}"
	assert_success
	refute_output --partial "env "
	assert_line "sudo apt-get update"
}

@test '--proxy overrides an ambient value' {
	_run_clean http_proxy=http://ambient:8080 \
		-n --no-sudo --proxy http://flag:3128 -s apt "${ALL_PM_FILE}"
	assert_success
	assert_output --partial "http_proxy=http://flag:3128"
	refute_output --partial "ambient:8080"
}

@test 'a verbatim cmd array inherits the exported proxy' {
	local f="${BATS_TEST_TMPDIR}/cmd_proxy.toml"
	# shellcheck disable=SC2016  # $https_proxy is read by the cmd's shell
	printf '[runtime.apt]\ncmd = ["sh", "-c", "echo saw:$https_proxy"]\n' >"${f}"
	_run_clean --no-sudo --proxy http://inherited:9 -s apt "${f}"
	assert_success
	assert_output --partial "saw:http://inherited:9"
}

@test 'verbose reports the resolved proxy variables' {
	_run_clean -n -v --no-sudo --proxy http://p.example:3128 -s apt \
		"${ALL_PM_FILE}"
	assert_success
	assert_output --partial "proxy:"
	assert_output --partial "http_proxy=http://p.example:3128"
}

@test '--proxy requires an argument' {
	_run_clean -n -s apt --proxy
	assert_failure
}

@test 'help documents --proxy and the standard variables' {
	run install-deps.sh --help
	assert_success
	assert_output --partial "--proxy"
	assert_output --partial "http_proxy"
	assert_output --partial "no_proxy"
}
