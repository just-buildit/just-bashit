# shellcheck disable=SC2154  # bats/common-setup export the harness vars
load 'test_helper/common-setup'
_common_setup

# `jbx -l SPEC` lists a shell script's functions by SOURCING it in a child
# bash, so the functions it gets from the libraries it sources are listed
# too. A script whose top level does work therefore ran, in full, under a
# flag that reads as inspection: `jbx -l setup-system` set the machine up
# (just-bashit#121). -l now reads the script first and refuses one whose top
# level runs a command, naming the line; it sources only a script whose top
# level declares, or keeps its work behind a main guard.

setup() {
	fixtures="${BATS_TEST_TMPDIR}/fixtures"
	ran="${BATS_TEST_TMPDIR}/ran"
	mkdir -p "${fixtures}"
	_serve_fixtures "${fixtures}"
	export XDG_CACHE_HOME="${BATS_TEST_TMPDIR}/cache"
}

@test '-l refuses a script with a top-level command, and does not run it' {
	printf '#!/usr/bin/env bash\nhello() { :; }\ntouch %q\n' "${ran}" \
		>"${fixtures}/tool.sh"
	run just-runit -l https://fixture.invalid/tool.sh
	assert_failure
	assert_output --partial 'will not source https://fixture.invalid/tool.sh'
	assert_output --partial 'line 3 of'
	assert_output --partial "touch ${ran}"
	refute [ -e "${ran}" ]
}

@test '-l lists a main-guarded script without running its main' {
	# Each function's body holds what would end it or open a top-level
	# command if read line by line: a } in a string, in a heredoc and in a
	# <<- heredoc, case patterns, a fi in a heredoc.
	cat >"${fixtures}/tool.sh" <<-EOF
		#!/usr/bin/env bash
		set -euo pipefail
		IFS=\$'\\n\\t'
		read -r -d '' HELP <<-'TXT' || true
			Usage: tool
			touch ${ran}
		TXT
		function alpha {
			echo "}"
			cat <<'TXT'
		}
		fi
		touch ${ran}
		TXT
		}
		beta() {
			case "\${1:-}" in
			a | b) echo ")" ;;
			*) echo "\$(echo "}")" ;;
			esac
		}
		function gamma() {
			if [[ -n \${1:-} ]]; then
				cat <<-'TXT'
					}
					touch ${ran}
				TXT
			fi
		}
		if [[ "\${BASH_SOURCE[0]}" == "\$0" ]]; then
			touch ${ran}
			alpha "\$@"
		fi
	EOF
	run just-runit -l https://fixture.invalid/tool.sh
	assert_success
	assert_output "$(printf 'alpha\nbeta\ngamma')"
	refute [ -e "${ran}" ]
}

@test '-l refuses a command hidden after a function whose body has a heredoc' {
	cat >"${fixtures}/tool.sh" <<-EOF
		helper() {
			cat <<'TXT'
		}
		TXT
		}
		touch ${ran}
	EOF
	run just-runit -l https://fixture.invalid/tool.sh
	assert_failure
	assert_output --partial 'line 6 of'
	refute [ -e "${ran}" ]
}

@test '-l still lists the functions a script gets from a library it sources' {
	printf 'from_lib() { :; }\n' >"${BATS_TEST_TMPDIR}/lib.sh"
	printf 'source %q\nown() { :; }\n' "${BATS_TEST_TMPDIR}/lib.sh" \
		>"${fixtures}/tool.sh"
	run just-runit -l https://fixture.invalid/tool.sh
	assert_success
	assert_output "$(printf 'from_lib\nown')"
}

@test '-l refuses setup-system, which has no main guard' {
	cp "${PROJECT_ROOT}/src/just_bashit/setup-system.sh" "${fixtures}/"
	run just-runit -l https://fixture.invalid/setup-system.sh
	assert_failure
	assert_output --partial 'runs a command at its top level'
}

# Every just-bashit library opens with the "must be sourced" guard,
# `(return 0 2>/dev/null) || ...`; -l must list each of them, whatever
# else its top level holds.
@test '-l lists every just-bashit library' {
	local lib name n=0
	for lib in "${PROJECT_ROOT}"/src/just_bashit/*.sh; do
		grep -q '^(return 0 2>/dev/null) ||' "${lib}" || continue
		name="${lib##*/}"
		cp "${lib}" "${fixtures}/${name}"
		run just-runit -l "https://fixture.invalid/${name}"
		assert_success
		assert [ -n "${output}" ]
		n=$((n + 1))
	done
	assert [ "${n}" -gt 0 ]
}
