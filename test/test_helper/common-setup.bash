#!/usr/bin/env bash

_common_setup() {
	load 'test_helper/bats-support/load'
	load 'test_helper/bats-assert/load'
	# get the containing directory of this file
	# use $BATS_TEST_FILENAME instead of ${BASH_SOURCE[0]} or $0,
	# as those will point to the bats executable's location or the preprocessed file respectively
	# shellcheck disable=SC2154
	PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." >/dev/null 2>&1 && pwd)"
	# make executables in src/just_bashit/ visible to PATH
	PATH="$PROJECT_ROOT/src/just_bashit:$PATH"
	export HELP_REGEX='Usage:'               # Check each script/function at least has usage.
	export BASH_XTRACEFD=${BASH_XTRACEFD:-2} # Use kcov's pipe fd when running under kcov; else stderr.
}

# _hide_windows_path NAME... — take every directory on a Windows drive mount
# off PATH, then fail if any NAME is still reachable.
#
# For a test that fakes "WSL with Windows' PATH left out" by moving its stub
# out of PATH. On a real WSL box with interop, Windows' own System32 is on
# PATH as well, so the real powershell.exe answered instead of the stub: the
# sshd test drove the genuine elevated setup and raised a UAC prompt on the
# desktop (Debian 13 WSL2, 2026-10-03). CI never saw it, since a Linux
# runner has no Windows drive mounted.
#
# The drives come from the REAL /proc/mounts, never JB_PROC_MOUNTS: that one
# is the test's fake, and the danger is the machine's own C:. The check runs
# before the script under test, so a failure here has driven nothing.
_hide_windows_path() {
	local roots root dir keep name kept=""
	roots="$(awk '$3 == "drvfs" || $4 ~ /(^|,)aname=drvfs/ { print $2 }' \
		/proc/mounts 2>/dev/null || true)"
	local IFS=:
	for dir in ${PATH}; do
		keep=1
		while IFS= read -r root; do
			[[ -n ${root} && ${dir} == "${root}"/* ]] && keep=0
		done <<<"${roots}"
		[[ ${keep} -eq 1 ]] && kept="${kept:+${kept}:}${dir}"
	done
	export PATH="${kept}"
	for name in "$@"; do
		if command -v "${name}" >/dev/null 2>&1; then
			echo "a real ${name} is still on PATH ($(command -v "${name}")); refusing to run" >&2
			return 1
		fi
	done
}

# _bin_without NAME... -- print a directory of symlinks to every program in
# /usr/local/bin, /usr/bin and /bin EXCEPT the named ones. Set PATH to it
# (plus what the test needs) to run as if they were not installed. Editing
# PATH cannot hide a program -- /bin is /usr/bin on Debian, and arch keeps
# pacman in /usr/bin -- but a PATH naming only this directory can.
_bin_without() {
	# shellcheck disable=SC2154  # BATS_TEST_TMPDIR is bats'
	local bin="${BATS_TEST_TMPDIR}/bin-without" dir prog name skip
	mkdir -p "${bin}"
	for dir in /usr/local/bin /usr/bin /bin; do
		[[ -d ${dir} ]] || continue
		for prog in "${dir}"/*; do
			name="${prog##*/}"
			for skip in "$@"; do
				[[ ${name} == "${skip}" ]] && continue 2
			done
			[[ -e "${bin}/${name}" ]] || ln -s "${prog}" "${bin}/${name}"
		done
	done
	printf '%s\n' "${bin}"
}
