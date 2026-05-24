#!/bin/bash
# ############################################################################
# EXECUTABLE: inspect.sh                                                      #
# PACKAGE: just-bashit version 0.1.5                                         #
# ############################################################################
# Query installed versions of system deps from a TOML deps file, plus system #
# and compiler info. Output is valid TOML (suitable as a lock file).         #
# ############################################################################
set -euo pipefail
IFS=$'\n\t'

VERBOSE=0
WRITE_LOCK=0
LOCK_FILE="jb.versions"
SECTION_OVERRIDE=""
GROUPS_STR=""
GROUPS_EXPLICIT=0
DEPS_FILE=""

read -r -d '' HELP <<-'EOF' || true
	Usage: inspect.sh [OPTIONS] [DEPS_FILE]

	  Query installed versions of system packages listed in a TOML deps file,
	  together with system and compiler information. Output is valid TOML,
	  suitable for committing as jb.versions to record the build environment.
	  Input resolution: DEPS_FILE arg > jb-deps.toml > jb.toml > stdin.

	  Output sections:
	    [system]    os, kernel, arch, glibc
	    [compiler]  gcc, clang, rustc, python3, cmake (any found on PATH)
	    [group.pm]  installed version of each package in the deps file;
	                cmd sections are noted but versions are not queried

	  jb.versions records what IS installed — it does not pin versions or
	  affect what install-deps installs.

	Options:
	  -h / --help              Show this message and exit.
	  -v / --verbose           Print resolved section and groups to stderr.
	  -w / --write [FILE]      Also write output to FILE (default: jb.versions).
	  -s / --section SECTION   Override auto-detected package manager.
	  -g / --groups  GROUP     Comma-separated groups to inspect (default: all
	                           groups in deps file, or [tools.inspect].groups).

	Arguments:
	  DEPS_FILE  Path to TOML deps file. Omit to auto-discover.
EOF

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
	case "$1" in
	-h | --help)
		echo "${HELP}"
		exit 0
		;;
	-v | --verbose)
		VERBOSE=1
		shift
		;;
	-w | --write)
		WRITE_LOCK=1
		if [[ $# -gt 1 && "${2}" != -* ]]; then
			LOCK_FILE="${2}"
			shift 2
		else
			shift
		fi
		;;
	-s | --section)
		SECTION_OVERRIDE="${2:?Option $1 requires an argument.}"
		shift 2
		;;
	-g | --groups)
		GROUPS_STR="${2:?Option $1 requires an argument.}"
		GROUPS_EXPLICIT=1
		shift 2
		;;
	-*)
		echo "Invalid option: $1"
		echo "${HELP}"
		exit 1
		;;
	*)
		DEPS_FILE="$1"
		shift
		;;
	esac
done

_log() { [[ ${VERBOSE} -eq 1 ]] && echo "$*" >&2 || true; }

# ---------------------------------------------------------------------------
# _detect_section: infer package manager from the running OS.
# ---------------------------------------------------------------------------
_detect_section() {
	local os
	os="$(uname -s)"
	case "${os}" in
	Darwin) echo "brew"; return ;;
	Linux)
		local ID="" ID_LIKE=""
		[ -f /etc/os-release ] && . /etc/os-release
		case "${ID_LIKE:-} ${ID:-}" in
		*debian* | *ubuntu*) echo "apt" ;;
		*arch* | *cachyos* | *manjaro*) echo "pacman" ;;
		*fedora* | *rhel* | *centos* | *rocky* | *alma*) echo "dnf" ;;
		*suse*) echo "zypper" ;;
		*alpine*) echo "apk" ;;
		*)
			echo "error: unrecognized distro (ID='${ID}')" >&2
			exit 1
			;;
		esac
		;;
	MINGW* | MSYS* | CYGWIN*) echo "msys2" ;;
	*) echo "error: unsupported OS '${os}'" >&2; exit 1 ;;
	esac
}

# ---------------------------------------------------------------------------
# _parse_section: extract packages from [group.section] in TOML (stdin).
# ---------------------------------------------------------------------------
_parse_section() {
	local group="$1" section="$2"
	local target="[${group}.${section}]"
	awk -v target="${target}" '
		/^\[/ { in_s = ($0 == target); in_l = 0; next }
		in_s && /packages[[:space:]]*=/ {
			in_l = 1; s = $0
			sub(/.*packages[[:space:]]*=[[:space:]]*\[/, "", s)
			if (index(s, "]") > 0) { sub(/\].*/, "", s); in_l = 0 }
			n = split(s, a, "\"")
			for (i = 2; i <= n; i += 2) if (a[i] != "") print a[i]
			next
		}
		in_l && /\]/ {
			s = $0; sub(/\].*/, "", s)
			n = split(s, a, "\"")
			for (i = 2; i <= n; i += 2) if (a[i] != "") print a[i]
			in_l = 0; next
		}
		in_l {
			n = split($0, a, "\"")
			for (i = 2; i <= n; i += 2) if (a[i] != "") print a[i]
		}
	'
}

# ---------------------------------------------------------------------------
# _parse_cmd: extract cmd=[...] from [group.section] in TOML (stdin).
# ---------------------------------------------------------------------------
_parse_cmd() {
	local group="$1" section="$2"
	local target="[${group}.${section}]"
	awk -v target="${target}" '
		/^\[/ { in_s = ($0 == target); in_l = 0; next }
		in_s && /cmd[[:space:]]*=/ {
			in_l = 1; s = $0
			sub(/.*cmd[[:space:]]*=[[:space:]]*\[/, "", s)
			if (index(s, "]") > 0) { sub(/\].*/, "", s); in_l = 0 }
			n = split(s, a, "\"")
			for (i = 2; i <= n; i += 2) if (a[i] != "") print a[i]
			next
		}
		in_l && /\]/ {
			s = $0; sub(/\].*/, "", s)
			n = split(s, a, "\"")
			for (i = 2; i <= n; i += 2) if (a[i] != "") print a[i]
			in_l = 0; next
		}
		in_l {
			n = split($0, a, "\"")
			for (i = 2; i <= n; i += 2) if (a[i] != "") print a[i]
		}
	'
}

# ---------------------------------------------------------------------------
# _toml_tool_groups: extract groups=[...] from [tools.NAME] (stdin).
# ---------------------------------------------------------------------------
_toml_tool_groups() {
	local tool="$1"
	awk -v target="[tools.${tool}]" '
		/^\[/ { in_s = ($0 == target); in_l = 0; next }
		in_s && /groups[[:space:]]*=/ {
			in_l = 1; s = $0
			sub(/.*groups[[:space:]]*=[[:space:]]*\[/, "", s)
			if (index(s, "]") > 0) { sub(/\].*/, "", s); in_l = 0 }
			n = split(s, a, "\"")
			for (i = 2; i <= n; i += 2) if (a[i] != "") printf "%s,", a[i]
			next
		}
		in_l && /\]/ {
			s = $0; sub(/\].*/, "", s)
			n = split(s, a, "\"")
			for (i = 2; i <= n; i += 2) if (a[i] != "") printf "%s,", a[i]
			in_l = 0; next
		}
		in_l {
			n = split($0, a, "\"")
			for (i = 2; i <= n; i += 2) if (a[i] != "") printf "%s,", a[i]
		}
	'
}

# ---------------------------------------------------------------------------
# _discover_groups: find all group names with known-PM sections (stdin).
# Preserves file order; prints comma-separated names.
# ---------------------------------------------------------------------------
_discover_groups() {
	awk '
		/^\[/ {
			gsub(/^\[|\]/, "")
			n = split($0, a, ".")
			if (n == 2) {
				pm = a[2]
				if (pm == "apt"   || pm == "pacman" || pm == "brew" ||
				    pm == "dnf"   || pm == "zypper" || pm == "apk"  ||
				    pm == "msys2") {
					if (!(a[1] in seen)) {
						seen[a[1]] = 1
						order[++count] = a[1]
					}
				}
			}
		}
		END {
			for (i = 1; i <= count; i++)
				printf "%s%s", (i > 1 ? "," : ""), order[i]
		}
	'
}

# ---------------------------------------------------------------------------
# _pkg_version_<pm>: query one package's installed version.
# Prints the version string, or nothing if not installed.
# ---------------------------------------------------------------------------
_pkg_version_pacman() {
	pacman -Q "$1" 2>/dev/null | awk '{print $2}' || true
}
_pkg_version_apt() {
	dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true
}
_pkg_version_brew() {
	brew list --versions "$1" 2>/dev/null | awk '{print $2}' || true
}
_pkg_version_dnf() {
	rpm -q --queryformat '%{VERSION}-%{RELEASE}' "$1" 2>/dev/null || true
}
_pkg_version_zypper() {
	rpm -q --queryformat '%{VERSION}-%{RELEASE}' "$1" 2>/dev/null || true
}
_pkg_version_apk() {
	# "apk info pkg" first line: "pkg-version description"
	local line
	line=$(apk info "$1" 2>/dev/null | head -1) || true
	[ -n "${line}" ] && printf '%s' "${line%% *}" | sed "s/^${1}-//" || true
}
_pkg_version_msys2() {
	pacman -Q "$1" 2>/dev/null | awk '{print $2}' || true
}

# ---------------------------------------------------------------------------
# _tool_version: first line of a tool's --version output; empty if missing.
# ---------------------------------------------------------------------------
_tool_version() {
	local cmd="$1"; shift
	command -v "${cmd}" >/dev/null 2>&1 || return 0
	"${cmd}" "$@" 2>/dev/null | head -1 || true
}

# ---------------------------------------------------------------------------
# _do_inspect: emit all TOML output to stdout.
# ---------------------------------------------------------------------------
_do_inspect() {
	printf '# jb.versions — generated by jbx inspect %s\n' \
		"$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
	printf '# regenerate: jbx inspect -w\n'
	printf '\n'

	# [system] ----------------------------------------------------------------
	printf '[system]\n'
	local _os_name="" _os_version="" _glibc=""
	if [ -f /etc/os-release ]; then
		# shellcheck source=/dev/null
		_os_name=$(. /etc/os-release && printf '%s' "${NAME:-}")
		_os_version=$(. /etc/os-release \
			&& printf '%s' "${VERSION_ID:-${BUILD_ID:-rolling}}")
	fi
	printf 'os = "%s (%s)"\n' "${_os_name:-unknown}" "${_os_version:-unknown}"
	printf 'kernel = "%s"\n' "$(uname -r)"
	printf 'arch = "%s"\n' "$(uname -m)"
	_glibc=$(getconf GNU_LIBC_VERSION 2>/dev/null \
		|| ldd --version 2>/dev/null | head -1 || true)
	[ -n "${_glibc}" ] && printf 'glibc = "%s"\n' "${_glibc}"
	printf '\n'

	# [compiler] --------------------------------------------------------------
	printf '[compiler]\n'
	local _v
	_v=$(_tool_version gcc --version)
	[ -n "${_v}" ] && printf 'gcc = "%s"\n' "${_v}"
	_v=$(_tool_version clang --version)
	[ -n "${_v}" ] && printf 'clang = "%s"\n' "${_v}"
	_v=$(_tool_version rustc --version)
	[ -n "${_v}" ] && printf 'rustc = "%s"\n' "${_v}"
	_v=$(_tool_version python3 --version)
	[ -n "${_v}" ] && printf 'python3 = "%s"\n' "${_v}"
	_v=$(_tool_version cmake --version)
	[ -n "${_v}" ] && printf 'cmake = "%s"\n' "${_v}"
	printf '\n'

	# [group.section] for each group ------------------------------------------
	local _group _cmd _pkgs _pkg _ver
	while IFS= read -r _group; do
		[ -z "${_group}" ] && continue

		# cmd sections: note the command; no versions to query.
		_cmd=()
		while IFS= read -r _c; do _cmd+=("${_c}"); done \
			< <(printf '%s' "${CONTENT}" | _parse_cmd "${_group}" "${SECTION}")
		if [ "${#_cmd[@]}" -gt 0 ]; then
			printf '[%s.%s]\n' "${_group}" "${SECTION}"
			(IFS=' '; printf '# cmd = %s\n' "${_cmd[*]}")
			printf '# versions not queried for custom cmd sections\n'
			printf '\n'
			continue
		fi

		_pkgs=()
		while IFS= read -r _p; do _pkgs+=("${_p}"); done \
			< <(printf '%s' "${CONTENT}" | _parse_section "${_group}" "${SECTION}")
		[ "${#_pkgs[@]}" -eq 0 ] && continue

		printf '[%s.%s]\n' "${_group}" "${SECTION}"
		for _pkg in "${_pkgs[@]}"; do
			_ver=$("_pkg_version_${SECTION}" "${_pkg}")
			if [ -n "${_ver}" ]; then
				printf '%s = "%s"\n' "${_pkg}" "${_ver}"
			else
				printf '# %s = not installed\n' "${_pkg}"
			fi
		done
		printf '\n'
	done < <(tr ',' '\n' <<<"${GROUPS_STR}")
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [ -n "${DEPS_FILE}" ]; then
	CONTENT=$(cat "${DEPS_FILE}")
elif [ -f "jb-deps.toml" ]; then
	CONTENT=$(cat "jb-deps.toml")
elif [ -f "jb.toml" ]; then
	CONTENT=$(cat "jb.toml")
else
	CONTENT=$(cat)
fi

if [[ ${GROUPS_EXPLICIT} -eq 0 ]]; then
	_toml_g=$(printf '%s' "${CONTENT}" | _toml_tool_groups "inspect" \
		| sed 's/,$//')
	if [[ -n "${_toml_g}" ]]; then
		GROUPS_STR="${_toml_g}"
	else
		GROUPS_STR=$(printf '%s' "${CONTENT}" | _discover_groups)
	fi
fi

SECTION="${SECTION_OVERRIDE:-$(_detect_section)}"
_log "section: ${SECTION}"
_log "groups:  ${GROUPS_STR}"

if [[ ${WRITE_LOCK} -eq 1 ]]; then
	_do_inspect | tee "${LOCK_FILE}"
	echo "wrote ${LOCK_FILE}" >&2
else
	_do_inspect
fi
