#!/usr/bin/env bash
# The suite's egress trap (just-bashit#147): no test may reach the network.
#
# network.bats once called live example.com, so a 503 from its CDN turned an
# unrelated PR red. Every test now answers a fetch from a shim -- a fake
# curl/wget/ping first on PATH, or _serve_fixtures -- and this file is what
# keeps it that way without anyone having to register a new test.
#
# bats runs setup_suite once before every file in this directory, so the trap
# covers the whole suite, any `make test BATS_ARGS=...` subset, and kcov's
# `make coverage` run alike. It puts a trap curl, wget and ping first on
# PATH; a test's own shim, prepended later, still wins. A trap call that only
# names no remote target -- `curl --help`, a file:// URL, a server on
# localhost -- runs the real tool. A remote URL, or any host given to ping, is
# written to the log and refused with curl's "could not resolve host" status,
# and teardown_suite fails the run naming every one, so a test that expected
# the fetch to fail still turns the suite red. GIT_ALLOW_PROTOCOL is the same
# fence for git: only file:// remotes, which are all a test may use.
#
# network.bats proves the trap is armed and logs, so a trap that stopped
# being installed fails a test rather than passing in silence.

setup_suite() {
	# shellcheck disable=SC2154  # BATS_SUITE_TMPDIR is bats'
	local trap="${BATS_SUITE_TMPDIR}/egress-trap" log name real
	log="${BATS_SUITE_TMPDIR}/egress.log"
	mkdir -p "${trap}"
	: >"${log}"
	for name in curl wget ping; do
		real="$(command -v "${name}" 2>/dev/null || true)"
		# The paths are baked into the shim rather than read from the
		# environment, so a test that runs under `env -i PATH="${PATH}"`
		# still logs to the right file.
		{
			echo '#!/usr/bin/env bash'
			printf 'name=%q real=%q log=%q\n' "${name}" "${real}" "${log}"
			cat <<-'EOF'
				# Remote unless every target is local: a file:// URL, or the
				# loopback a test's own server listens on. A call with no
				# target at all (`curl --help`) only asks the tool about itself.
				remote=0 target=0 prev=""
				for arg in "$@"; do
					case "${prev}" in
					-o | -O | --output | --output-document)
						prev="${arg}"
						continue
						;;
					esac
					prev="${arg}"
					case "${arg}" in
					file://*) target=1 ;;
					*://localhost[:/]* | *://localhost | *://127.0.0.1*) target=1 ;;
					*://*) remote=1 ;;
					localhost | localhost:* | 127.0.0.1*) target=1 ;;
					-*) ;;
					*)
						# A schemeless host (`curl example.com`), told from
						# an option's value by its shape and by not being
						# a file.
						[[ ! -e ${arg} && ${arg} =~ ^([A-Za-z0-9-]+\.)+[A-Za-z][A-Za-z0-9-]*(:[0-9]+)?(/.*)?$ ]] &&
							remote=1
						;;
					esac
				done
				if ((remote == 0 && target == 0)) && [[ ${name} == ping ]]; then
					for arg in "$@"; do [[ ${arg} == -* ]] || remote=1; done
				fi
				if ((remote == 1)); then
					printf '%s: %s %s\n' "${BATS_TEST_FILENAME##*/}" \
						"${name}" "$*" >>"${log}"
					echo "${name}: egress refused by the test suite's trap" \
						"(just-bashit#147): $*" >&2
					exit 6
				fi
				[[ -n ${real} ]] || exit 127
				exec "${real}" "$@"
			EOF
		} >"${trap}/${name}"
		chmod +x "${trap}/${name}"
	done
	export JB_EGRESS_LOG="${log}" JB_EGRESS_TRAP="${trap}"
	export GIT_ALLOW_PROTOCOL=file PATH="${trap}:${PATH}"
	# just-runit caches what it fetches under XDG_CACHE_HOME. Left at the
	# user's own ~/.cache, a warm cache answered a fetch that a cold CI
	# runner makes -- so a test reached the network only in CI, and wrote to
	# the user's home locally. Every run starts cold, here.
	export XDG_CACHE_HOME="${BATS_SUITE_TMPDIR}/cache"
}

teardown_suite() {
	[[ -s ${JB_EGRESS_LOG} ]] || return 0
	echo "A test reached for the network (just-bashit#147). Answer it from a" \
		"shim first on PATH, as network.bats and _serve_fixtures do:" >&2
	sed 's/^/  /' "${JB_EGRESS_LOG}" >&2
	return 1
}
