# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, HELP_REGEX set by bats/common-setup
load 'test_helper/common-setup'
_common_setup

# Every test runs against a throwaway HOME and a throwaway "Windows profile",
# so nothing here can read the developer's real keys or write to a real
# %USERPROFILE%.
#
# The Windows side is stubbed rather than skipped. CI has Linux runners and
# nothing else, so the alternative is a tool tested only by hand on the one
# platform it targets -- which means eventually not tested at all. The stubs
# stand in for the four things this script asks Windows for, and icacls
# records its arguments so the ACL calls can be asserted rather than assumed.
setup() {
	HOME="${BATS_TEST_TMPDIR}/home"
	WINHOME="${BATS_TEST_TMPDIR}/winprofile"
	STUBS="${BATS_TEST_TMPDIR}/stubs"
	ICACLS_LOG="${BATS_TEST_TMPDIR}/icacls.log"
	PROC="${BATS_TEST_TMPDIR}/proc-version"
	export HOME WINHOME STUBS ICACLS_LOG

	mkdir -p "${HOME}/.ssh" "${WINHOME}" "${STUBS}"
	: >"${ICACLS_LOG}"

	# A convincing /proc/version, and the override that points the script at it.
	echo "Linux version 5.15.0-microsoft-standard-WSL2" >"${PROC}"
	export JB_PROC_VERSION="${PROC}"

	# A private key is recognised by its header, so the body can be anything.
	printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nsecret\n' >"${HOME}/.ssh/id_test"
	printf 'ssh-ed25519 AAAA test\n' >"${HOME}/.ssh/id_test.pub"
	# Not a key: must never be published.
	printf 'github.com ssh-ed25519 AAAA\n' >"${HOME}/.ssh/known_hosts"

	cat >"${STUBS}/cmd.exe" <<-EOF
		#!/bin/bash
		printf 'C:\\\\Users\\\\tester\r\n'
	EOF

	cat >"${STUBS}/whoami.exe" <<-EOF
		#!/bin/bash
		printf 'TESTHOST\\\\tester\r\n'
	EOF

	# -u turns the fake Windows profile into the temp dir standing in for it;
	# -w does the reverse, which is all the script asks of it.
	cat >"${STUBS}/wslpath" <<-EOF
		#!/bin/bash
		case "\$1" in
		  -u) printf '%s\n' "\${2/C:\\\\Users\\\\tester/${WINHOME}}" ;;
		  -w) rest="\${2#${WINHOME}}"; printf 'C:\\\\Users\\\\tester%s\n' "\$(printf '%s' "\$rest" | tr '/' '\\\\')" ;;
		  *)  printf '%s\n' "\$2" ;;
		esac
	EOF

	cat >"${STUBS}/icacls.exe" <<-EOF
		#!/bin/bash
		printf '%s\n' "\$*" >>"${ICACLS_LOG}"
	EOF

	chmod +x "${STUBS}"/*
	PATH="${STUBS}:${PATH}"
	export PATH

	SCRIPT="${PROJECT_ROOT}/src/just_bashit/ssh-to-windows.sh"
}

@test "ssh-to-windows: --help exits 0 and prints usage" {
	run bash "${SCRIPT}" --help
	[ "${status}" -eq 0 ]
	[[ ${output} == *"Usage: ssh-to-windows.sh"* ]]
}

@test "ssh-to-windows: refuses to run when this is not WSL" {
	echo "Linux version 6.1.0-generic" >"${PROC}"
	run bash "${SCRIPT}"
	[ "${status}" -eq 1 ]
	[[ ${output} == *"not running under WSL"* ]]
}

@test "ssh-to-windows: an unknown option is an error" {
	run bash "${SCRIPT}" --nope
	[ "${status}" -eq 1 ]
	[[ ${output} == *"unknown option"* ]]
}

@test "ssh-to-windows: publishes the key and its .pub, and not known_hosts" {
	run bash "${SCRIPT}"
	[ "${status}" -eq 0 ]
	[ -f "${WINHOME}/.ssh/id_test" ]
	[ -f "${WINHOME}/.ssh/id_test.pub" ]
	[ ! -e "${WINHOME}/.ssh/known_hosts" ]
	# Copied, not merely created.
	[ "$(cat "${WINHOME}/.ssh/id_test")" = "$(cat "${HOME}/.ssh/id_test")" ]
}

@test "ssh-to-windows: locks the ACL down on the directory and the private key" {
	run bash "${SCRIPT}"
	[ "${status}" -eq 0 ]
	# The directory grant is inheritable, so keys land correct.
	grep -q 'inheritance:r' "${ICACLS_LOG}"
	grep -q '(OI)(CI)F' "${ICACLS_LOG}"
	# The private key is granted to exactly one principal.
	grep -q 'id_test /inheritance:r /grant:r TESTHOST\\tester:F' "${ICACLS_LOG}"
	# The public key needs no ACL surgery, and must not get any.
	run grep -q 'id_test.pub' "${ICACLS_LOG}"
	[ "${status}" -ne 0 ]
}

@test "ssh-to-windows: a second run copies nothing but re-asserts the ACL" {
	run bash "${SCRIPT}"
	[ "${status}" -eq 0 ]
	: >"${ICACLS_LOG}"
	run bash "${SCRIPT}"
	[ "${status}" -eq 0 ]
	[[ ${output} == *"0 file(s) written"* ]]
	# The copy is not what rots; the ACL is. It is re-applied regardless.
	grep -q 'id_test /inheritance:r' "${ICACLS_LOG}"
}

@test "ssh-to-windows: a differing Windows key is reported, not clobbered" {
	run bash "${SCRIPT}"
	[ "${status}" -eq 0 ]
	printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nDIFFERENT\n' >"${WINHOME}/.ssh/id_test"

	run bash "${SCRIPT}"
	[ "${status}" -eq 2 ]
	[[ ${output} == *"DIFFERS"* ]]
	grep -q DIFFERENT "${WINHOME}/.ssh/id_test"

	run bash "${SCRIPT}" --force
	[ "${status}" -eq 0 ]
	run grep -q DIFFERENT "${WINHOME}/.ssh/id_test"
	[ "${status}" -ne 0 ]
}

@test "ssh-to-windows: --key publishes only the named key" {
	printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nother\n' >"${HOME}/.ssh/id_other"
	run bash "${SCRIPT}" --key id_test
	[ "${status}" -eq 0 ]
	[ -f "${WINHOME}/.ssh/id_test" ]
	[ ! -e "${WINHOME}/.ssh/id_other" ]
}

@test "ssh-to-windows: --key refuses a file that is not a private key" {
	run bash "${SCRIPT}" --key known_hosts
	[ "${status}" -eq 1 ]
	[[ ${output} == *"is not a private key"* ]]
}

@test "ssh-to-windows: --dry-run writes nothing and still shows the ACL calls" {
	run bash "${SCRIPT}" --dry-run
	[ "${status}" -eq 0 ]
	[ ! -e "${WINHOME}/.ssh/id_test" ]
	[ ! -s "${ICACLS_LOG}" ]
	# The ACL change is the important half; a dry run that hid it would be
	# worse than useless.
	[[ ${output} == *"would: icacls.exe"* ]]
	[[ ${output} == *"inheritance:r"* ]]
}
