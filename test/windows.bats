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
