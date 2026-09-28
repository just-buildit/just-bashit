# shellcheck disable=SC2154  # bats/common-setup export the harness vars
load 'test_helper/common-setup'
_common_setup

# win-exe against a fake C: drive: a directory, and a mount table naming it,
# the way a WSL shell reached over ssh sees the machine.
setup() {
	# shellcheck source=/dev/null
	source "${PROJECT_ROOT}/src/just_bashit/windows.sh"
	ROOT="${BATS_TEST_TMPDIR}/c"
	mkdir -p "${ROOT}/Windows/System32/WindowsPowerShell/v1.0" \
		"${ROOT}/Program Files/PowerShell/7"
	printf 'C:\\134 %s 9p rw,aname=drvfs;path=C:\\ 0 0\n' "${ROOT}" >"${BATS_TEST_TMPDIR}/mounts"
	export JB_PROC_MOUNTS="${BATS_TEST_TMPDIR}/mounts"
}

# An executable stand-in for a Windows program.
_exe() { printf '#!/bin/sh\n' >"$1" && chmod +x "$1"; }

@test 'win-exe: finds System32, Windows PowerShell and PowerShell 7 by full path' {
	_exe "${ROOT}/Windows/System32/jbtest-cmd.exe"
	_exe "${ROOT}/Windows/System32/WindowsPowerShell/v1.0/jbtest-powershell.exe"
	_exe "${ROOT}/Program Files/PowerShell/7/jbtest-pwsh.exe"
	run win-exe jbtest-cmd.exe
	assert_output "${ROOT}/Windows/System32/jbtest-cmd.exe"
	run win-exe jbtest-powershell.exe
	assert_output "${ROOT}/Windows/System32/WindowsPowerShell/v1.0/jbtest-powershell.exe"
	run win-exe jbtest-pwsh.exe
	assert_output "${ROOT}/Program Files/PowerShell/7/jbtest-pwsh.exe"
}

@test 'win-exe: PATH wins over the C: mount' {
	_exe "${ROOT}/Windows/System32/jbtest-cmd.exe"
	mkdir -p "${BATS_TEST_TMPDIR}/bin"
	_exe "${BATS_TEST_TMPDIR}/bin/jbtest-cmd.exe"
	PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" run win-exe jbtest-cmd.exe
	assert_output "${BATS_TEST_TMPDIR}/bin/jbtest-cmd.exe"
}

@test 'win-exe: fails, printing nothing, with no C: mount and nothing on PATH' {
	: >"${JB_PROC_MOUNTS}"
	run win-exe jbtest-cmd.exe
	assert_failure
	assert_output ""
}

@test 'win-exe: a file that is not executable is not an answer' {
	# No .exe suffix: MSYS (the windows runner) calls any *.exe executable
	# whatever its mode, so the suffix would test MSYS, not the -x check.
	printf 'x' >"${ROOT}/Windows/System32/jbtest-noexec"
	run win-exe jbtest-noexec
	assert_failure
}

# win-admin-channel against stand-ins: cmd.exe answers for this machine, and
# ssh plays the far end's reply to the one probe it is sent.
_channel_stubs() {
	mkdir -p "${BATS_TEST_TMPDIR}/bin"
	cat >"${BATS_TEST_TMPDIR}/bin/cmd.exe" <<-'STUB'
		#!/bin/bash
		case "$*" in
		*USERNAME*) printf 'tester\r\n' ;;
		*COMPUTERNAME*) printf 'TESTHOST\r\n' ;;
		esac
	STUB
	# FAR_NAME / FAR_HIGH / FAR_RC are what the far end answers.
	cat >"${BATS_TEST_TMPDIR}/bin/ssh" <<-'STUB'
		#!/bin/bash
		[ "${FAR_RC:-0}" -eq 0 ] || exit "${FAR_RC}"
		printf '%s\r\n%s\r\n' "${FAR_NAME:-TESTHOST}" "${FAR_HIGH:-True}"
	STUB
	chmod +x "${BATS_TEST_TMPDIR}"/bin/*
	export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" JB_WIN_HOST=192.0.2.1
}

@test 'win-admin-channel: this machine, elevated, is a channel' {
	_channel_stubs
	run win-admin-channel
	assert_success
	assert_output "tester@192.0.2.1"
}

@test 'win-admin-channel: a far end that is another machine is not' {
	_channel_stubs
	FAR_NAME=SOMEONE-ELSE run win-admin-channel
	assert_failure
	assert_output ""
}

@test 'win-admin-channel: a session that is not elevated is not' {
	_channel_stubs
	FAR_HIGH=False run win-admin-channel
	assert_failure
}

@test 'win-admin-channel: no sshd answering is not' {
	_channel_stubs
	FAR_RC=255 run win-admin-channel
	assert_failure
}

# A box with no hostname command (a minimal Fedora image) and an existing
# ~/.ssh: sourcing this under `set -e` killed the caller with 127, silently.
@test 'sourcing survives a missing hostname, and offers no key' {
	mkdir -p "${BATS_TEST_TMPDIR}/home/.ssh" "${BATS_TEST_TMPDIR}/nohost"
	printf '#!/bin/sh\nexit 127\n' >"${BATS_TEST_TMPDIR}/nohost/hostname"
	chmod +x "${BATS_TEST_TMPDIR}/nohost/hostname"
	# A script FILE, not `bash -c`: coverage runs under kcov, whose
	# instrumentation reads BASH_SOURCE -- unset in a -c string under -u.
	cat >"${BATS_TEST_TMPDIR}/caller.sh" <<-EOF
		set -euo pipefail
		. '${PROJECT_ROOT}/src/just_bashit/windows.sh'
		printf '%s ' "\${WIN_SSH_OPTS[@]}"
	EOF
	HOME="${BATS_TEST_TMPDIR}/home" PATH="${BATS_TEST_TMPDIR}/nohost:${PATH}" \
		run bash "${BATS_TEST_TMPDIR}/caller.sh"
	assert_success
	refute_output --partial "-i"
}
