# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, HELP_REGEX set by bats/common-setup
# shellcheck disable=SC2030,SC2031  # bats runs each @test in its own
# process, which shellcheck models as a subshell: a variable set in one
# test is genuinely gone by the next, which is the isolation these want.
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
	assert_output --regexp '^(apt|pacman|brew|dnf|zypper|apk|msys2|winget)$'
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
		# pacman is what separates MSYS2 from Git Bash; every runner that
		# reaches this arm is MSYS2 and has it.
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

# ---------------------------------------------------------------------------
# winget-bin, and the Windows arm of get-pkg-mgr
#
# The platform comes from JB_UNAME_S and the interpreter from JB_WINGET.
# Neither can be expressed with PATH: this machine may be any OS, and the
# WindowsApps interop directory that carries winget.exe is on PATH under both
# MSYS2 and WSL, so a name removed from one spelling is still reachable by
# the other.
# ---------------------------------------------------------------------------

# A PATH holding only what get-pkg-mgr needs, which is nothing — every
# lookup it makes is a bash builtin. Replacing PATH wholesale, rather than
# editing an entry out of it, is what actually makes pacman unreachable:
# /bin is a symlink to /usr/bin on Debian, so removing one leaves the other.
_empty_path_dir() {
	local d="${BATS_TEST_TMPDIR}/nopath"
	mkdir -p "${d}"
	printf '%s\n' "${d}"
}

_stub_exe() {
	local path="${BATS_TEST_TMPDIR}/$1"
	printf '#!/bin/sh\nexit 0\n' >"${path}"
	chmod +x "${path}"
	printf '%s\n' "${path}"
}

@test 'winget-bin honours JB_WINGET' {
	export JB_WINGET="/somewhere/winget.exe"
	run winget-bin
	assert_success
	assert_output "/somewhere/winget.exe"
}

@test 'winget-bin reports none when JB_WINGET is empty' {
	export JB_WINGET=""
	run winget-bin
	assert_failure
	assert_output ''
}

@test 'winget-bin prefers the bare name over the .exe' {
	local d="${BATS_TEST_TMPDIR}/both"
	mkdir -p "${d}"
	printf '#!/bin/sh\nexit 0\n' >"${d}/winget"
	printf '#!/bin/sh\nexit 0\n' >"${d}/winget.exe"
	chmod +x "${d}/winget" "${d}/winget.exe"
	PATH="${d}:${PATH}" run winget-bin
	assert_success
	assert_output 'winget'
}

@test 'get-pkg-mgr picks msys2 on Windows when pacman is there' {
	local d
	d="$(_empty_path_dir)"
	printf '#!/bin/sh\nexit 0\n' >"${d}/pacman"
	chmod +x "${d}/pacman"
	export JB_UNAME_S="MINGW64_NT-10.0-22631"
	# Saved and put back rather than exported: bats' own teardown runs `rm`
	# after the test body, and a PATH left empty takes coreutils with it.
	local saved="${PATH}"
	PATH="${d}"
	run get-pkg-mgr
	PATH="${saved}"
	assert_success
	assert_output 'msys2'
}

@test 'get-pkg-mgr picks winget on Windows without pacman' {
	local d stub
	d="$(_empty_path_dir)"
	stub="$(_stub_exe winget-probe)"
	export JB_UNAME_S="MINGW64_NT-10.0-22631"
	export JB_WINGET="${stub}"
	local saved="${PATH}"
	PATH="${d}"
	run get-pkg-mgr
	PATH="${saved}"
	assert_success
	assert_output 'winget'
}

@test 'get-pkg-mgr falls back to msys2 when neither is there' {
	local d
	d="$(_empty_path_dir)"
	export JB_UNAME_S="MINGW64_NT-10.0-22631"
	export JB_WINGET=""
	local saved="${PATH}"
	PATH="${d}"
	run get-pkg-mgr
	PATH="${saved}"
	assert_success
	assert_output 'msys2'
}

@test 'get-pkg-version winget reads the version beside the matching id' {
	local stub="${BATS_TEST_TMPDIR}/winget-list"
	# Two rows, a Name column carrying spaces, and CRLF line endings —
	# which is what winget.exe actually writes. The version is the token
	# after the exact id, not a fixed field number.
	cat >"${stub}" <<-'EOF'
		#!/usr/bin/env bash
		printf 'Name       Id                   Version Source\r\n'
		printf 'Py Launcher Py.Launcher         1.0.0   winget\r\n'
		printf 'PowerShell Microsoft.PowerShell 7.6.6.0 winget\r\n'
	EOF
	chmod +x "${stub}"
	export JB_WINGET="${stub}"
	run get-pkg-version winget Microsoft.PowerShell
	assert_success
	assert_output '7.6.6.0'
}

@test 'get-pkg-version winget prints nothing for a package not listed' {
	local stub="${BATS_TEST_TMPDIR}/winget-none"
	cat >"${stub}" <<-'EOF'
		#!/usr/bin/env bash
		printf 'No installed package found matching input criteria.\r\n'
		exit 20
	EOF
	chmod +x "${stub}"
	export JB_WINGET="${stub}"
	run get-pkg-version winget No.Such.Package
	assert_success
	assert_output ''
}

@test 'get-pkg-version winget prints nothing when there is no winget' {
	export JB_WINGET=""
	run get-pkg-version winget Microsoft.PowerShell
	assert_success
	assert_output ''
}

# ---------------------------------------------------------------------------
# install-uv (#171). On Windows uv comes from winget, which picks the
# machine's native build: astral's install.sh reads only `uname -m`, and an
# emulated x64 Git Bash on ARM64 Windows reads x86_64 there. winget is a stub
# that logs its arguments; `install` links uv into LOCALAPPDATA's
# Microsoft/WinGet/Links, as the real one does. astral's installer is a
# fixture behind the suite's fixture curl, writing ~/.local/bin/uv.
# ---------------------------------------------------------------------------

# ARGS: more programs to leave off PATH. _bin_without builds one directory
# per test, so it is called once, here.
_uv_setup() {
	export HOME="${BATS_TEST_TMPDIR}/home" LOCALAPPDATA="${BATS_TEST_TMPDIR}/lad"
	UV_LINKS="${LOCALAPPDATA}/Microsoft/WinGet/Links"
	WINGET_LOG="${BATS_TEST_TMPDIR}/winget.log"
	mkdir -p "${HOME}" "${LOCALAPPDATA}"
	local fx="${BATS_TEST_TMPDIR}/fixtures"
	mkdir -p "${fx}"
	# shellcheck disable=SC2016  # expanded when the installer runs
	printf '%s\n' 'mkdir -p "${HOME}/.local/bin"' \
		'printf "#!/bin/sh\necho uv-from-install-sh\n" >"${HOME}/.local/bin/uv"' \
		'chmod +x "${HOME}/.local/bin/uv"' >"${fx}/install.sh"
	_serve_fixtures "${fx}"
	: >"${JB_FIXTURES_LOG}"
	# No uv anywhere but where an installer puts it.
	PATH="${BATS_TEST_TMPDIR}/fixture-curl:$(_bin_without uv "$@")"
	# The winget stub: `list` finds the id only once it is installed.
	cat >"${BATS_TEST_TMPDIR}/winget" <<-EOF
		#!/usr/bin/env bash
		echo "\$*" >>'${WINGET_LOG}'
		case "\$1" in
		list) [ -e '${UV_LINKS}/uv' ] || exit 20 ;;
		install)
			[ -e '${BATS_TEST_TMPDIR}/winget-fails' ] && exit 1
			mkdir -p '${UV_LINKS}'
			printf '#!/bin/sh\necho uv-from-winget\n' >'${UV_LINKS}/uv'
			chmod +x '${UV_LINKS}/uv'
			;;
		esac
	EOF
	chmod +x "${BATS_TEST_TMPDIR}/winget"
	export JB_WINGET="${BATS_TEST_TMPDIR}/winget"
}

@test 'install-uv on Windows installs astral-sh.uv through winget' {
	_uv_setup
	export JB_UNAME_S="MINGW64_NT-10.0-26100"
	run install-uv
	assert_success
	assert_output "${UV_LINKS}"
	run grep -c '^install --id astral-sh.uv --exact --source winget --silent' "${WINGET_LOG}"
	assert_output 1
	# astral's installer was never fetched.
	run grep -c 'install.sh' "${JB_FIXTURES_LOG}"
	assert_output 0
}

@test 'install-uv on Windows does not reinstall what winget lists' {
	_uv_setup
	export JB_UNAME_S="MSYS_NT-10.0-26100"
	mkdir -p "${UV_LINKS}"
	printf '#!/bin/sh\n' >"${UV_LINKS}/uv"
	chmod +x "${UV_LINKS}/uv"
	run install-uv
	assert_success
	assert_output "${UV_LINKS}"
	run grep -c '^install' "${WINGET_LOG}"
	assert_output 0
}

@test 'install-uv on Windows without winget runs install.sh' {
	_uv_setup
	export JB_UNAME_S="MINGW64_NT-10.0-26100" JB_WINGET=""
	run install-uv
	assert_success
	assert_output "${HOME}/.local/bin"
	run grep -c '^https://astral.sh/uv/install.sh$' "${JB_FIXTURES_LOG}"
	assert_output 1
}

@test 'install-uv falls back to install.sh when winget fails, and says so' {
	_uv_setup
	export JB_UNAME_S="MINGW64_NT-10.0-26100"
	touch "${BATS_TEST_TMPDIR}/winget-fails"
	install-uv >"${BATS_TEST_TMPDIR}/out" 2>"${BATS_TEST_TMPDIR}/err"
	assert_equal "$(<"${BATS_TEST_TMPDIR}/out")" "${HOME}/.local/bin"
	run grep -c 'winget did not install astral-sh.uv' "${BATS_TEST_TMPDIR}/err"
	assert_output 1
}

@test 'install-uv off Windows runs install.sh, never winget' {
	_uv_setup
	export JB_UNAME_S="Linux"
	run install-uv
	assert_success
	assert_output "${HOME}/.local/bin"
	refute [ -e "${WINGET_LOG}" ]
}

@test 'install-uv refuses, naming awk, where there is none' {
	_uv_setup awk gawk mawk
	export JB_UNAME_S="Linux"
	run install-uv
	assert_failure
	assert_output --partial "needs awk"
	run grep -c 'install.sh' "${JB_FIXTURES_LOG}"
	assert_output 0
}

@test 'install-uv -n prints the winget command on Windows and runs nothing' {
	_uv_setup
	export JB_UNAME_S="MINGW64_NT-10.0-26100"
	IFS=$'\n\t' run install-uv -n
	assert_success
	assert_output "${JB_WINGET} install --id astral-sh.uv --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity"
	refute [ -e "${WINGET_LOG}" ]
}

@test 'install-uv -n prints the install.sh line off Windows' {
	_uv_setup
	export JB_UNAME_S="Darwin"
	run install-uv -n
	assert_success
	assert_output "curl -LsSf https://astral.sh/uv/install.sh | sh"
}

# `jbx --no-verify` documents covering the nested uv install; it reaches
# install-uv's own fetch of astral's installer as JB_NO_VERIFY=1.
@test 'install-uv passes --insecure to curl only under JB_NO_VERIFY=1' {
	_uv_setup
	export JB_UNAME_S="Linux"
	local real="${BATS_TEST_TMPDIR}/fixture-curl/curl"
	mv "${real}" "${real}.real"
	printf '#!/usr/bin/env bash\necho "$*" >>%q\nexec %q "$@"\n' \
		"${BATS_TEST_TMPDIR}/curl-args" "${real}.real" >"${real}"
	chmod +x "${real}"
	JB_NO_VERIFY=1 run install-uv
	assert_success
	run grep -c -- '--insecure' "${BATS_TEST_TMPDIR}/curl-args"
	assert_output 1
	rm -f "${HOME}/.local/bin/uv" "${BATS_TEST_TMPDIR}/curl-args"
	run install-uv
	assert_success
	run grep -c -- '--insecure' "${BATS_TEST_TMPDIR}/curl-args"
	assert_output 0
}
