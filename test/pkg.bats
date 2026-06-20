# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, HELP_REGEX set by bats/common-setup
load 'test_helper/common-setup'
source 'src/just_bashit/pkg.sh'
_common_setup

# ---------------------------------------------------------------------------
# get-pkg-mgr
# ---------------------------------------------------------------------------

@test 'get-pkg-mgr returns a non-empty string' {
	run get-pkg-mgr
	assert_success
	assert [ -n "${output}" ]
}

@test 'get-pkg-mgr returns a known package manager' {
	run get-pkg-mgr
	assert_success
	assert_output --regexp '^(apt|pacman|brew|dnf|zypper|apk|msys2)$'
}

@test 'get-pkg-mgr matches running OS' {
	local os
	os="$(uname -s)"
	run get-pkg-mgr
	assert_success
	case "${os}" in
	Darwin)
		assert_output 'brew'
		;;
	Linux)
		local ID=""
		[ -f /etc/os-release ] && . /etc/os-release
		case "${ID_LIKE:-} ${ID:-}" in
		*debian* | *ubuntu*) assert_output 'apt' ;;
		*arch* | *cachyos* | *manjaro*) assert_output 'pacman' ;;
		*fedora* | *rhel* | *centos* | *rocky* | *alma*) assert_output 'dnf' ;;
		*suse*) assert_output 'zypper' ;;
		*alpine*) assert_output 'apk' ;;
		esac
		;;
	MINGW* | MSYS* | CYGWIN*)
		assert_output 'msys2'
		;;
	esac
}

# ---------------------------------------------------------------------------
# get-pkg-version
# ---------------------------------------------------------------------------

@test 'get-pkg-version returns nothing for unknown package' {
	local pm
	pm="$(get-pkg-mgr)"
	run get-pkg-version "${pm}" "this-package-does-not-exist-xyzzy-99"
	assert_success
	assert_output ''
}

@test 'get-pkg-version returns version for installed package' {
	local pm
	pm="$(get-pkg-mgr)"
	# bash is always installed — use it as the known-installed package.
	# Package name differs by PM.
	local pkg
	case "${pm}" in
	apt) pkg="bash" ;;
	pacman) pkg="bash" ;;
	brew) pkg="bash" ;;
	dnf) pkg="bash" ;;
	zypper) pkg="bash" ;;
	apk) pkg="bash" ;;
	msys2) pkg="bash" ;;
	*) skip "unknown PM ${pm}" ;;
	esac
	run get-pkg-version "${pm}" "${pkg}"
	assert_success
	assert [ -n "${output}" ]
}

@test 'get-pkg-version unknown PM prints error and fails' {
	run get-pkg-version "notapm" "curl"
	assert_failure
	assert_output --partial "unknown package manager"
}

@test 'get-pkg-version apt queries dpkg' {
	if ! command -v dpkg-query >/dev/null 2>&1; then
		skip "dpkg-query not available"
	fi
	run get-pkg-version apt bash
	assert_success
	assert [ -n "${output}" ]
}

@test 'get-pkg-version pacman queries pacman' {
	if ! command -v pacman >/dev/null 2>&1; then
		skip "pacman not available"
	fi
	run get-pkg-version pacman bash
	assert_success
	assert [ -n "${output}" ]
}

@test 'get-pkg-version msys2 uses pacman backend' {
	if ! command -v pacman >/dev/null 2>&1; then
		skip "pacman not available"
	fi
	run get-pkg-version msys2 bash
	assert_success
	assert [ -n "${output}" ]
}

# ---------------------------------------------------------------------------
# -h / help for all functions
# ---------------------------------------------------------------------------

@test 'get-pkg-mgr -h shows usage' {
	run get-pkg-mgr -h
	assert_success
	assert_output --regexp "${HELP_REGEX}"
}

@test 'get-pkg-version -h shows usage' {
	run get-pkg-version -h
	assert_success
	assert_output --regexp "${HELP_REGEX}"
}
