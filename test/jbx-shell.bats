# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, PROJECT_ROOT set by bats/common-setup
load 'test_helper/common-setup'

# ---------------------------------------------------------------------------
# jbx-shell.sh: the `jbx` function applies what a setup-system run changed to
# the shell that ran it. Every scenario runs under each POSIX shell present
# -- bash, sh (dash on Debian, busybox ash on Alpine), zsh -- because it is
# sourced into whatever shell the user has, on every distro; CI's matrix
# supplies the distros.
# ---------------------------------------------------------------------------

setup() {
	_common_setup
	export HOME="${BATS_TEST_TMPDIR}/home"
	export XDG_STATE_HOME="${HOME}/.local/state"
	mkdir -p "${HOME}" "${BATS_TEST_TMPDIR}/bin"
	LIB="${PROJECT_ROOT}/src/just_bashit/jbx-shell.sh"
	STUBDIR="${BATS_TEST_TMPDIR}/bin"
	PROFILE="${BATS_TEST_TMPDIR}/profile.sh"
	BASHRC="${BATS_TEST_TMPDIR}/bashrc.sh"
	NEWDIR="${BATS_TEST_TMPDIR}/newbin"
	printf 'JB_TEST_PROFILE=applied\n' >"${PROFILE}"
	printf 'JB_TEST_BASHRC=applied\n' >"${BASHRC}"
	# The `jbx` binary setup-system would be: it writes the marker only when
	# the function asked (JB_CALLER_APPLIES=1), and exits with STUB_RC.
	cat >"${STUBDIR}/jbx" <<-EOF
		#!/bin/sh
		if [ "\${JB_CALLER_APPLIES:-0}" = 1 ]; then
			m="\${XDG_STATE_HOME}/just-bashit/reload"
			mkdir -p "\${m%/*}"
			printf 'profile %s\nbashrc %s\npath %s\n' "${PROFILE}" "${BASHRC}" "${NEWDIR}" >"\$m"
		fi
		exit "\${STUB_RC:-0}"
	EOF
	chmod +x "${STUBDIR}/jbx"
	export LIB STUBDIR PROFILE BASHRC NEWDIR
}

# The scenario, as one shell script: source the library, call jbx, report
# what the SAME shell now sees.
_scenario() {
	cat <<-'EOF'
		PATH="${STUBDIR}:${PATH}"
		. "${LIB}"
		jbx setup-system
		rc=$?
		echo "rc=${rc}"
		echo "profile=${JB_TEST_PROFILE:-unset}"
		echo "bashrc=${JB_TEST_BASHRC:-unset}"
		case ":${PATH}:" in *":${NEWDIR}:"*) echo "path=yes" ;; *) echo "path=no" ;; esac
		[ -e "$(jb_reload_marker)" ] && echo "marker=left" || echo "marker=gone"
	EOF
}

_shells() {
	local s
	for s in bash sh dash zsh busybox; do
		command -v "${s}" >/dev/null 2>&1 && printf '%s\n' "${s}"
	done
}

# _shell_is_bash SHELL -- prints "bash" when SHELL is bash under any name.
_shell_is_bash() {
	# shellcheck disable=SC2016  # expanded by the shell under test
	if [[ $1 == busybox ]]; then
		busybox sh -c 'echo ${BASH_VERSION:+bash}'
	else
		"$1" -c 'echo ${BASH_VERSION:+bash}'
	fi
}

_run_in() {
	if [[ $1 == busybox ]]; then
		run busybox sh -c "$(_scenario)"
	else
		run "$1" -c "$(_scenario)"
	fi
}

@test 'jbx applies the run to the calling shell, in every POSIX shell here' {
	local s n=0
	for s in $(_shells); do
		_run_in "${s}"
		assert_success
		assert_output --partial "rc=0"
		assert_output --partial "profile=applied"
		assert_output --partial "path=yes"
		assert_output --partial "marker=gone"
		assert_output --partial "jbx: applied to this shell:"
		# bashrc.sh is bash-only: applied under bash, never elsewhere. Asked
		# of the shell itself, as the function asks it: arch, fedora and
		# macOS ship `sh` as bash (POSIX mode, BASH_VERSION set), Debian's
		# is dash -- a name says nothing.
		if [[ -n "$(_shell_is_bash "${s}")" ]]; then
			assert_output --partial "bashrc=applied"
		else
			assert_output --partial "bashrc=unset"
		fi
		n=$((n + 1))
	done
	# Never a vacuous pass: bash at least is always here.
	[[ ${n} -ge 1 ]]
}

@test 'jbx returns the exit status of the run, and still applies' {
	local s
	for s in $(_shells); do
		STUB_RC=3 _run_in "${s}"
		assert_output --partial "rc=3"
		assert_output --partial "profile=applied"
	done
}

# A run that left no marker (nothing changed) applies nothing and says
# nothing.
@test 'jbx with no marker changes nothing and stays quiet' {
	printf '#!/bin/sh\nexit 0\n' >"${STUBDIR}/jbx"
	local s
	for s in $(_shells); do
		_run_in "${s}"
		assert_success
		assert_output --partial "profile=unset"
		refute_output --partial "applied to this shell"
	done
}

# A second identical directive does not stack PATH entries.
@test 'jbx puts a path on PATH once, however often it is applied' {
	run bash -c "PATH=\"${NEWDIR}:\${PATH}\"; $(_scenario); echo \"\${PATH}\" | tr ':' '\n' | grep -cx \"${NEWDIR}\""
	assert_success
	assert_line "1"
}

# get-jb.sh installs jbx-shell.sh where setup-system's shell step does --
# beside bashrc.sh, in setup-system's PREFIX. The directory is spelled in
# both; this holds the two spellings equal.
@test 'get-jb.sh and setup-system agree on the config directory' {
	local a b
	a="$(sed -n 's/^PREFIX="\(.*\)"$/\1/p' "${PROJECT_ROOT}/src/just_bashit/setup-system.sh")"
	b="$(sed -n 's/^[[:space:]]*local jb_conf="\(.*\)"$/\1/p' "${PROJECT_ROOT}/src/just_bashit/get-jb.sh")"
	[[ -n ${a} ]]
	assert_equal "${b}" "${a}"
}
