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

# The elevation check is ONE expression (#184): what win-elevated asks this
# machine's PowerShell is what win-admin-channel asks the far end.
_ps_stub() {
	mkdir -p "${BATS_TEST_TMPDIR}/bin"
	cat >"${BATS_TEST_TMPDIR}/bin/powershell.exe" <<-'STUB'
		#!/bin/bash
		printf '%s\n' "${@: -1}" >"${BATS_TEST_TMPDIR}/ps.cmd"
		printf '%s\r\n' "${LOCAL_HIGH:-False}"
	STUB
	chmod +x "${BATS_TEST_TMPDIR}/bin/powershell.exe"
	export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
	unset JB_WIN_ELEVATED
}

@test 'win-elevated: True from PowerShell is elevated, anything else is not' {
	_ps_stub
	LOCAL_HIGH=True run win-elevated
	assert_success
	run cat "${BATS_TEST_TMPDIR}/ps.cmd"
	assert_output "${WIN_ELEVATED_PS}"
	LOCAL_HIGH=False run win-elevated
	assert_failure
}

@test 'win-elevated: the check names whoami.exe by full path, for the High SID' {
	# Git Bash's PATH puts Git's own whoami first, which refuses /groups.
	assert [ -n "${WIN_ELEVATED_PS}" ]
	[[ ${WIN_ELEVATED_PS} == *"Join-Path \$env:SystemRoot 'System32\whoami.exe'"* ]]
	[[ ${WIN_ELEVATED_PS} == *S-1-16-12288* ]]
}

@test 'win-admin-channel asks the far end the same elevation check' {
	_channel_stubs
	cat >"${BATS_TEST_TMPDIR}/bin/ssh" <<-'STUB'
		#!/bin/bash
		printf '%s\n' "${@: -1}" >"${BATS_TEST_TMPDIR}/ssh.cmd"
		printf 'TESTHOST\r\nTrue\r\n'
	STUB
	run win-admin-channel
	assert_success
	run cat "${BATS_TEST_TMPDIR}/ssh.cmd"
	assert_output "\$env:COMPUTERNAME; ${WIN_ELEVATED_PS}"
}

@test 'win-elevated: JB_WIN_ELEVATED answers instead of PowerShell' {
	_ps_stub
	LOCAL_HIGH=True JB_WIN_ELEVATED=0 run win-elevated
	assert_failure
	JB_WIN_ELEVATED=1 run win-elevated
	assert_success
	assert [ ! -e "${BATS_TEST_TMPDIR}/ps.cmd" ]
}

# win-admin-route: elevated, then the channel, then --yes skips, else UAC.
@test 'win-admin-route: elevated wins, then the channel, then --yes, then UAC' {
	_channel_stubs
	JB_WIN_ELEVATED=1 run win-admin-route 1
	assert_output "elevated"
	JB_WIN_ELEVATED=0 run win-admin-route 1
	assert_output "ssh tester@192.0.2.1"
	JB_WIN_ELEVATED=0 FAR_RC=255 run win-admin-route 1
	assert_output "skip"
	JB_WIN_ELEVATED=0 FAR_RC=255 run win-admin-route 0
	assert_output "uac"
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
