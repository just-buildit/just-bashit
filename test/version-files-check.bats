# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, PROJECT_ROOT set by common-setup
load 'test_helper/common-setup'
_common_setup

# ---------------------------------------------------------------------------
# version_files_check.sh — the gate guarding the release path.
#
# Every case below is a failure this repo has actually shipped. They are
# tested rather than trusted because the gate itself can regress into a
# weaker shape that still looks right: the first draft checked whether a
# FILE was registered instead of whether each declaring LINE was, and that
# version passed the just-runit `_VERSION` bug green.
#
# Each test builds a miniature repo and mutates its bumpversion table, so
# nothing here depends on the real pyproject.toml staying as it is today.
# ---------------------------------------------------------------------------

HDR_PAD="                                         "

setup() {
	REPO="${BATS_TEST_TMPDIR}/repo"
	mkdir -p "${REPO}/src/just_bashit" "${REPO}/scripts"
	cp "${PROJECT_ROOT}/scripts/version_files_check.sh" "${REPO}/scripts/"

	# Two shipped files: one with only a header, one that also declares a
	# quoted _VERSION — the shape that went unregistered in 0.1.4.
	printf '#!/bin/bash\n# PACKAGE: just-bashit version 1.2.3%s#\n' \
		"${HDR_PAD}" >"${REPO}/src/just_bashit/alpha.sh"
	printf '#!/bin/bash\n# PACKAGE: just-bashit version 1.2.3%s#\n_VERSION="1.2.3"\n' \
		"${HDR_PAD}" >"${REPO}/src/just_bashit/runner"

	printf 'version = "1.2.3"\n' >"${REPO}/manifest.toml"

	cat >"${REPO}/pyproject.toml" <<EOF
[project]
version = "1.2.3"

[tool.bumpversion]
current_version = "1.2.3"

[[tool.bumpversion.files]]
filename = "src/just_bashit/alpha.sh"
search = "# PACKAGE: just-bashit version {current_version}${HDR_PAD}#"
replace = "# PACKAGE: just-bashit version {new_version}${HDR_PAD}#"

[[tool.bumpversion.files]]
filename = "src/just_bashit/runner"
search = "# PACKAGE: just-bashit version {current_version}${HDR_PAD}#"
replace = "# PACKAGE: just-bashit version {new_version}${HDR_PAD}#"

[[tool.bumpversion.files]]
filename = "src/just_bashit/runner"
search = "_VERSION=\\"{current_version}\\""
replace = "_VERSION=\\"{new_version}\\""

[[tool.bumpversion.files]]
filename = "manifest.toml"
search = "version = \\"{current_version}\\""
replace = "version = \\"{new_version}\\""
EOF
}

_gate() {
	VERSION_FILES_ROOT="${REPO}" run bash "${REPO}/scripts/version_files_check.sh"
}

@test 'a correctly registered tree passes' {
	_gate
	assert_success
	assert_output --partial "every declaring line covered"
}

@test 'a registered file that does not exist fails (the jb.toml rename)' {
	sed -i 's|filename = "manifest.toml"|filename = "gone.toml"|' \
		"${REPO}/pyproject.toml"
	_gate
	assert_failure
	assert_output --partial "registers files that do not exist"
	assert_output --partial "gone.toml"
}

@test 'a search that matches nothing fails (header padding drift)' {
	# One extra space: bump-my-version would report success and change
	# nothing, which is the failure mode worth catching.
	sed -i "0,/^search = \"# PACKAGE/s//search = \"# PACKAGE: just-bashit version {current_version} ${HDR_PAD}#\" #/" \
		"${REPO}/pyproject.toml"
	_gate
	assert_failure
	assert_output --partial "match nothing in their file"
}

@test 'a registered file with an unregistered line fails (just-runit 0.1.4)' {
	# Drop only the _VERSION entry. The file stays registered by its header,
	# so a file-level check passes this — and did, before it was rewritten.
	python3 - "${REPO}/pyproject.toml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
i = s.index('search = "_VERSION')
start = s.rindex('[[tool.bumpversion.files]]', 0, i)
end = s.index('[[tool.bumpversion.files]]', i)
open(p, 'w').write(s[:start] + s[end:])
PY
	_gate
	assert_failure
	assert_output --partial "no bumpversion search covers them"
	assert_output --partial "src/just_bashit/runner"
}

@test 'a shipped file with no entry at all fails (make-run.sh 0.4.0)' {
	printf '#!/bin/bash\n# PACKAGE: just-bashit version 1.2.3%s#\n' \
		"${HDR_PAD}" >"${REPO}/src/just_bashit/newcomer.sh"
	_gate
	assert_failure
	assert_output --partial "no bumpversion search covers them"
	assert_output --partial "newcomer.sh"
}

@test 'prose naming a released version is not a declaration' {
	# The reason this gate cannot simply grep for the version: source and
	# docs narrate releases, and bumping those sentences makes them false.
	printf '\n# This changed in 1.2.3, which is a fact about the past.\n' \
		>>"${REPO}/src/just_bashit/alpha.sh"
	_gate
	assert_success
}

@test 'a quoted version in an unregistered file is a declaration' {
	printf 'thing = "1.2.3"\n' >"${REPO}/src/just_bashit/data.toml"
	_gate
	assert_failure
	assert_output --partial "data.toml"
}

@test 'the config file itself is exempt' {
	# bump-my-version rewrites its own config natively; requiring an entry
	# for it would fail every correctly configured repo.
	_gate
	assert_success
	refute_output --partial "pyproject.toml:"
}

@test 'a table with no entries is an error, not a pass' {
	python3 - "${REPO}/pyproject.toml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
open(p, 'w').write(s[:s.index('[[tool.bumpversion.files]]')])
PY
	_gate
	assert_failure
	assert_output --partial "no [[tool.bumpversion.files]] entries"
}

@test 'a missing current_version is an error, not a pass' {
	sed -i '/^current_version = /d' "${REPO}/pyproject.toml"
	_gate
	assert_failure
	assert_output --partial "current_version"
}
