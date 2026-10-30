# shellcheck disable=SC2154  # bats/common-setup export the harness vars
load 'test_helper/common-setup'
_common_setup
bats_require_minimum_version 1.5.0

# `jbx -l SPEC` lists a shell script's functions. It used to SOURCE the
# script in a child bash, so a script whose top level does work ran, in
# full, under a flag that reads as inspection: `jbx -l setup-system` set the
# machine up (just-bashit#121). Refusing a top level that runs a command
# still left `X=$(cmd)` running cmd, an assignment (just-bashit#143). -l now
# reads the script and runs none of it: every test here counts the side
# effects of the fixture's top level, and requires none.

setup() {
	fixtures="${BATS_TEST_TMPDIR}/fixtures"
	ran="${BATS_TEST_TMPDIR}/ran"
	mkdir -p "${fixtures}"
	_serve_fixtures "${fixtures}"
	export XDG_CACHE_HOME="${BATS_TEST_TMPDIR}/cache"
}

@test '-l lists a script with a top-level command, and does not run it' {
	printf '#!/usr/bin/env bash\nhello() { :; }\ntouch %q\nbye() { :; }\n' \
		"${ran}" >"${fixtures}/tool.sh"
	run just-runit -l https://fixture.invalid/tool.sh
	assert_success
	assert_output "$(printf 'hello\nbye' | sort)"
	refute [ -e "${ran}" ]
}

# just-bashit#143: an assignment's command substitution ran when -l
# sourced the script, whatever the gate before it allowed.
@test '-l runs no command substitution in a top-level assignment' {
	cat >"${fixtures}/tool.sh" <<-EOF
		X=\$(echo sub >>${ran})
		_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && echo dir >>${ran})"
		[[ -n \$(echo test >>${ran}) ]] && Y=1
		f() { :; }
	EOF
	run just-runit -l https://fixture.invalid/tool.sh
	assert_success
	assert_output 'f'
	refute [ -e "${ran}" ]
}

@test '-l lists a function defined after an empty array assignment' {
	# shellcheck disable=SC2016  # the fixture's own expansions
	printf '_R=()\n_result() { _R+=("$1"); }\n' >"${fixtures}/tool.sh"
	run just-runit -l https://fixture.invalid/tool.sh
	assert_success
	assert_output '_result'
}

@test '-l lists the functions a top-level if defines, and runs neither branch' {
	cat >"${fixtures}/tool.sh" <<-EOF
		if [[ \$(echo cond >>${ran}) ]]; then
			on() { :; }
		else
			off() { :; }
		fi
	EOF
	run just-runit -l https://fixture.invalid/tool.sh
	assert_success
	assert_output "$(printf 'off\non')"
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

@test '-l does not run a command after a function whose body has a heredoc' {
	cat >"${fixtures}/tool.sh" <<-EOF
		helper() {
			cat <<'TXT'
		}
		TXT
		}
		touch ${ran}
	EOF
	run just-runit -l https://fixture.invalid/tool.sh
	assert_success
	assert_output 'helper'
	refute [ -e "${ran}" ]
}

@test '-l refuses a script it cannot read to the end, naming the line' {
	printf 'f() { :; }\ng() {\n\techo\n' >"${fixtures}/tool.sh"
	run just-runit -l https://fixture.invalid/tool.sh
	assert_failure
	assert_output --partial '-l cannot read https://fixture.invalid/tool.sh'
	assert_output --partial 'unterminated at end of file'
}

@test '-l still lists the functions a script gets from a library it sources' {
	# The library's top level does work too: it is read, not run.
	printf 'from_lib() { :; }\ntouch %q\n' "${ran}" \
		>"${BATS_TEST_TMPDIR}/lib.sh"
	printf 'source %q\nown() { :; }\n' "${BATS_TEST_TMPDIR}/lib.sh" \
		>"${fixtures}/tool.sh"
	run just-runit -l https://fixture.invalid/tool.sh
	assert_success
	assert_output "$(printf 'from_lib\nown')"
	refute [ -e "${ran}" ]
}

# A library named through an expansion is found by its last component
# beside the script -- where jbx co-fetches just-bashit's -- not by running
# the expansion; one that is not there is named on stderr.
@test '-l finds a library sourced through an expansion beside the script' {
	cp "${PROJECT_ROOT}"/src/just_bashit/*.sh "${fixtures}/"
	run --separate-stderr just-runit -l just-bashit:logging
	assert_success
	assert_line 'log'
	assert_line 'color-echo'
	assert [ -z "${stderr}" ]
	# shellcheck disable=SC2016  # the fixture's own expansions
	printf 'source "$(echo %q)/gone.sh"\nown() { :; }\n' "${ran}" \
		>"${fixtures}/tool.sh"
	run --separate-stderr just-runit -l https://fixture.invalid/tool.sh
	assert_success
	assert_output 'own'
	assert [ -n "${stderr}" ]
	[[ ${stderr} == *'gone.sh'*'found only by running the script'* ]] || false
	refute [ -e "${ran}" ]
}

@test '-l lists setup-system, which has no main guard, without running it' {
	cp "${PROJECT_ROOT}/src/just_bashit/setup-system.sh" "${fixtures}/"
	run just-runit -l https://fixture.invalid/setup-system.sh
	assert_success
	assert_line 'step_pwsh'
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

# kcov exports SHELLOPTS so the shells it traces pass their options on, and
# with it jbx's own `set -euo pipefail` reached the child that sources the
# script: `compgen -A function` returns 1 while no function exists yet, so the
# child died on its first line, and `make coverage` went red on main while
# `make test` passed. The child now starts from bash's default options. This
# runs -l with errexit and nounset exported, as under kcov, so `make test`
# sees what only coverage saw.
@test '-l lists a script when the caller exports its shell options, as kcov does' {
	printf '#!/usr/bin/env bash\nhello() { :; }\nworld() { :; }\n' \
		>"${fixtures}/tool.sh"
	# env -i: an exported function in the environment (bats has them) would
	# make the child's first compgen succeed and hide the failure.
	run env -i PATH="${PATH}" HOME="${HOME}" JB_FIXTURES="${JB_FIXTURES}" \
		XDG_CACHE_HOME="${XDG_CACHE_HOME}" \
		bash -c 'set -eu; export SHELLOPTS
			just-runit -l https://fixture.invalid/tool.sh'
	assert_success
	assert_output "$(printf 'hello\nworld')"
}

# kcov traces every bash it reaches through BASH_ENV, a file that turns on
# xtrace with a PS4 naming BASH_SOURCE. The child that sources the script
# read it too, and a script with `set -euo pipefail` left nounset on after
# sourcing, so the child's next line expanded that PS4 at its top level,
# where BASH_SOURCE is unset, and failed: this test's real counterpart went
# red under `make coverage` only. The child now runs without BASH_ENV.
@test '-l lists a strict script when a BASH_ENV tracer is set, as under kcov' {
	cat >"${fixtures}/tool.sh" <<-'EOF2'
		#!/usr/bin/env bash
		set -euo pipefail
		main() { :; }
		if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main; fi
	EOF2
	local tracer="${BATS_TEST_TMPDIR}/tracer.sh"
	# Single quotes in the file, as kcov writes it: PS4 is expanded at each
	# traced line, not once when the file is read.
	cat >"${tracer}" <<-'EOF2'
		set -x
		PS4='+trace@${BASH_SOURCE}@${LINENO}@'
	EOF2
	run --separate-stderr env -i PATH="${PATH}" HOME="${HOME}" \
		JB_FIXTURES="${JB_FIXTURES}" XDG_CACHE_HOME="${XDG_CACHE_HOME}" \
		BASH_ENV="${tracer}" just-runit -l https://fixture.invalid/tool.sh
	assert_success
	assert_output 'main'
}
