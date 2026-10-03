# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, PROJECT_ROOT set by bats/common-setup
load 'test_helper/common-setup'

# ---------------------------------------------------------------------------
# The bootstrap runs before anything is installed, so it may use only what a
# minimal image has. A Debian 13 WSL image has no awk: get-jb.sh "installed"
# uv through an installer that needed it, and `jbx setup-system` could not
# even resolve its alias -- the step that would have installed awk
# (2026-10-03). jbx (just-runit), get-jb.sh and install-deps.sh stay awk-free;
# setup-system's baseline then installs one for every later step.
# ---------------------------------------------------------------------------

setup() {
	_common_setup
}

# The scripts that run before setup-system's baseline lands.
_BOOTSTRAP=(just-runit get-jb.sh install-deps.sh toml.sh)

@test 'the bootstrap scripts never call awk' {
	local f hits=""
	for f in "${_BOOTSTRAP[@]}"; do
		# Comments may name awk (they say why it is absent), and
		# `command -v awk` may probe for it; nothing may run it.
		hits+="$(grep -nE '(^|[^[:alnum:]_-])[gm]?awk([[:space:]]|$)' \
			"${PROJECT_ROOT}/src/just_bashit/${f}" |
			grep -vE '^[0-9]+:[[:space:]]*#|command -v [gm]?awk' |
			sed "s|^|${f}:|")"
	done
	assert_equal "${hits}" ""
}

@test 'jbx resolves an alias on a machine with no awk' {
	local cache="${BATS_TEST_TMPDIR}/cache/just-runit" base url key now bin
	base="https://just-buildit.github.io"
	url="https://example.invalid/probe.sh"
	now="$(date +%s)"
	mkdir -p "${cache}"

	# The alias table, with the cases the parser must get right: a key in
	# another section, a comment, quoting and padding around the value.
	key="$(printf '%s' "${base}" | sha256sum | cut -d' ' -f1)"
	cat >"${cache}/aliases-${key}.toml" <<-EOF
		[elsewhere]
		probe = "https://example.invalid/wrong-section.sh"

		[aliases]
		# probe = "https://example.invalid/commented.sh"
		probe   =   "${url}"
	EOF
	printf 'ts=%s\nurl=%s/aliases.toml\n' "${now}" "${base}" \
		>"${cache}/aliases-${key}.meta"

	# The script the alias names, already cached, so nothing is fetched.
	key="$(printf '%s' "${url}" | sha256sum | cut -d' ' -f1)"
	printf '#!/usr/bin/env bash\necho PROBE-RAN\n' >"${cache}/${key}.sh"
	printf 'ts=%s\nurl=%s\n' "${now}" "${url}" >"${cache}/${key}.meta"

	bin="$(_bin_without awk gawk mawk nawk original-awk busybox)"
	run env -i HOME="${HOME}" XDG_CACHE_HOME="${BATS_TEST_TMPDIR}/cache" \
		PATH="${bin}" bash "${PROJECT_ROOT}/src/just_bashit/just-runit" probe
	refute_output --partial "awk: command not found"
	assert_success
	assert_output --partial "PROBE-RAN"
}
