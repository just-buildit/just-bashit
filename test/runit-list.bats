# shellcheck disable=SC2154  # bats/common-setup export the harness vars
load 'test_helper/common-setup'
_common_setup
bats_require_minimum_version 1.5.0

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
