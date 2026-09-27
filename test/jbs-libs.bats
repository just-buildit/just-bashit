# shellcheck disable=SC2154  # bats/common-setup export the harness vars
load 'test_helper/common-setup'
_common_setup

# jbx fetches a script from the jbs/ mirror on its own, then co-fetches the
# libraries named in just-runit's _JBS_LIBS so the script's
# `source "${_SCRIPT_DIR}/X.sh"` lines resolve beside it. The list is written
# by hand. A library a script sources but the list omits works from a
# checkout, where every sibling is present, and fails only under jbx, which
# no other test runs. windows.sh was nearly the first such library.

_jbs_libs() {
	awk '/^_JBS_LIBS=\(/ { on = 1; next } on && /^\)/ { exit } on' \
		"${PROJECT_ROOT}/src/just_bashit/just-runit" | tr -s ' \t' '\n' | sed '/^$/d'
}

_sourced_libs() {
	# shellcheck disable=SC2016  # the literal text a script writes, not an expansion
	grep -ho 'source "${_SCRIPT_DIR}/[A-Za-z0-9_-]*\.sh"' \
		"${PROJECT_ROOT}"/src/just_bashit/*.sh |
		sed 's|.*/\(.*\)\.sh"|\1|' | sort -u
}

@test 'every library a shipped script sources is on the jbx fetch list' {
	local libs sourced missing=()
	libs="$(_jbs_libs)"
	sourced="$(_sourced_libs)"
	# Armed: an empty side would pass by finding nothing to compare.
	[ -n "${libs}" ]
	[ -n "${sourced}" ]
	local l
	while read -r l; do
		grep -qx "${l}" <<<"${libs}" || missing+=("${l}")
	done <<<"${sourced}"
	if [ "${#missing[@]}" -gt 0 ]; then
		echo "sourced but not in _JBS_LIBS: ${missing[*]}" >&2
		return 1
	fi
}
